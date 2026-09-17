require "./spec_helper"

private def with_feature_file(&block : HDF5::File, String ->)
  path = File.join(Dir.tempdir, "hdf5_features_#{Process.pid}_#{Random::Secure.hex(8)}.h5")
  begin
    HDF5.open(path, :w) { |file| block.call(file, path) }
  ensure
    File.delete(path) if File.exists?(path)
  end
end

# Inject failures at the native boundary, leaving real storage and cleanup active.
module HDF5::Native
  class_property? fail_read : Bool = false
  class_property? fail_reclaim : Bool = false
  class_property? fail_write : Bool = false
  class_property? fail_attribute_write : Bool = false
  class_property extent_calls_until_failure : Int32 = -1
  class_property? fail_rename : Bool = false
  class_property? fail_close : Bool = false

  def self.h5dread(*args)
    status = previous_def(*args)
    fail_read? ? -1 : status
  end

  def self.h5dvlen_reclaim(*args)
    status = previous_def(*args)
    fail_reclaim? ? -1 : status
  end

  def self.h5dwrite(*args)
    return -1 if fail_write?
    previous_def(*args)
  end

  def self.h5awrite(*args)
    return -1 if fail_attribute_write?
    previous_def(*args)
  end

  def self.h5dset_extent(*args)
    if extent_calls_until_failure >= 0
      return -1 if extent_calls_until_failure == 0
      self.extent_calls_until_failure -= 1
    end
    previous_def(*args)
  end

  def self.h5arename(*args)
    if fail_rename? && args[1].starts_with?("__hdf5_cr_") && !args[2].starts_with?("__hdf5_cr_")
      self.fail_rename = false
      return -1
    end
    previous_def(*args)
  end

  def self.h5gclose(*args)
    return -1 if fail_close?
    previous_def(*args)
  end
end

describe "Crystal feature parity" do
  after_each do
    HDF5::Native.fail_read = false
    HDF5::Native.fail_reclaim = false
    HDF5::Native.fail_write = false
    HDF5::Native.fail_attribute_write = false
    HDF5::Native.extent_calls_until_failure = -1
    HDF5::Native.fail_rename = false
    HDF5::Native.fail_close = false
  end

  it "creates flat multidimensional data and checked Slice buffers" do
    with_feature_file do |file, _|
      values = [1, 2, 3, 4, 5, 6]
      ds = file.create_dataset("matrix", values, shape: {2, 3}, chunk: :auto)
      ds.shape.should eq([2_u64, 3_u64])
      ds.read.should eq(values)
      buffer = Slice(Int32).new(3, 0)
      ds.read_into(buffer, HDF5.s[1, HDF5.all])
      buffer.to_a.should eq([4, 5, 6])
      expect_raises(HDF5::ShapeMismatchError) { ds.read_into(Slice(Int32).new(2, 0)) }
      expect_raises(HDF5::ShapeMismatchError) { ds.write([1]) }
      expect_raises(HDF5::ShapeMismatchError) { ds.write(Slice[1]) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("bad", values, shape: {3, 3}) }
      file.exists?("bad").should be_false
      ds.write(Slice[7, 8, 9], HDF5.s[0, HDF5.all])
      ds.read_scalar(HDF5.s[0, 1]).should eq(8)
    end
  end

  it "distinguishes scalar, empty and Null datasets and attributes" do
    with_feature_file do |file, _|
      scalar = file.create_dataset("scalar", 1.5)
      scalar.shape.should eq([] of UInt64)
      scalar.scalar?.should be_true
      scalar.read.should eq([1.5])
      scalar.read_scalar.should eq(1.5)
      scalar.write(2.5)
      scalar.read_scalar.should eq(2.5)
      empty = file.create_dataset("empty", String, shape: {0, 3})
      empty.null?.should be_false
      empty.read.should be_empty
      empty.write([] of String)
      null = file.create_dataset("null", HDF5::Empty(Int16).new)
      null.null?.should be_true
      null.size.should eq(0)
      null.read_null.should be_a(HDF5::Empty(Int16))
      expect_raises(HDF5::ShapeMismatchError) { null.read }
      expect_raises(HDF5::ShapeMismatchError) { null.write([1_i16]) }
      expect_raises(HDF5::ShapeMismatchError) { null.append([1_i16]) }
      expect_raises(HDF5::ShapeMismatchError) { null.resize({1}) }
      file.attrs.create("null", HDF5::Empty(String).new)
      file.attrs.get_null("null", String).should be_a(HDF5::Empty(String))
      expect_raises(HDF5::ShapeMismatchError) { file.attrs.modify("null", "text") }
    end
  end

  it "round trips Bool and both complex precisions, including selections and attributes" do
    with_feature_file do |file, _|
      bits = file.create_dataset("bits", [false, true, false, true], shape: {2, 2}, chunk: {1, 2}, fill_value: true)
      bits.read.should eq([false, true, false, true])
      bits.fill_value.should be_true
      bits.read_scalar(HDF5.s[1, 1]).should be_true
      bits.write(true, HDF5.s[0, HDF5.all])
      bits.read.should eq([true, true, false, true])
      buffer = Slice(Bool).new(2, false)
      bits.read_into(buffer, HDF5.s[1, HDF5.all])
      buffer.to_a.should eq([false, true])
      z = [Complex.new(1, 2), Complex.new(3, 4)]
      c128 = file.create_dataset("complex128", z)
      c128.read.should eq(z)
      c128.read_scalar(HDF5.s[0]).should eq(z[0])
      c64values = z.map { |v| HDF5::Complex32.new(v) }
      c64 = file.create_dataset("complex64", c64values)
      c64.read.should eq(c64values)
      c64.read(HDF5.s[1..]).first.to_c.should eq(z[1])
      c64.write([HDF5::Complex32.new(9, 10)], HDF5.s[0])
      c64.read.first.to_c.should eq(Complex.new(9, 10))
      dtype = bits.datatype
      dtype.bool?.should be_true
      dtype.close
      dtype = c64.datatype
      dtype.complex?.should be_true
      dtype.byte_order.should eq(LibHDF5::ByteOrder::Little)
      dtype.close
      file.attrs["enabled"] = true
      file.attrs.get("enabled", Bool).should be_true
      file.attrs.create("complex", z, shape: {1, 2})
      file.attrs.get_array("complex", Complex).should eq(z)
      file.attrs.modify("complex", c64values, casting: HDF5::Casting::Safe)
      file.attrs.get_array("complex", Complex).should eq(z)
      file.attrs["bits"] = [false, true]
      file.attrs.get_array("bits", Bool).should eq([false, true])
    end
  end

  it "exposes numeric storage metadata and opt-in safe casts" do
    with_feature_file do |file, _|
      ds = file.create_dataset("small", [1_i16, 2_i16])
      ds.read.should eq([1_i16, 2_i16])
      ds.write([3_i64, 4_i64])
      ds.read.should eq([3_i16, 4_i16])
      ds.dataset.read(Int32, casting: HDF5::Casting::Safe).should eq([3, 4])
      expect_raises(HDF5::TypeMismatchError) { ds.write([5_i64, 6_i64], casting: HDF5::Casting::Safe) }
      expect_raises(HDF5::TypeMismatchError) { ds.dataset.read(Int8, casting: HDF5::Casting::Safe) }
      dtype = ds.datatype
      dtype.precision.should eq(16)
      dtype.offset.should eq(0)
      dtype.byte_order.should eq(LibHDF5::ByteOrder::Little)
      dtype.close
      small = file.create_dataset("scalar", Int8, fill_value: 7, casting: HDF5::Casting::Safe)
      small.read_scalar.should eq(7_i8)
      small.write(42, casting: HDF5::Casting::Safe)
      expect_raises(HDF5::TypeMismatchError) { small.write(300, casting: HDF5::Casting::Safe) }
      expect_raises(HDF5::TypeMismatchError) { small.write(1.5, casting: HDF5::Casting::Safe) }
      small.read_scalar.should eq(42_i8)
      file.attrs.create("small", Int8, 7, casting: HDF5::Casting::Safe)
      file.attrs.modify("small", 42, casting: HDF5::Casting::Safe)
      expect_raises(HDF5::TypeMismatchError) { file.attrs.modify("small", 300, casting: HDF5::Casting::Safe) }
      file.attrs.get("small", Int8).should eq(42_i8)
      complex = file.create_dataset("complex", Complex, shape: {2})
      complex.write([1, 2], casting: HDF5::Casting::Safe)
      complex.read.should eq([Complex.new(1), Complex.new(2)])
    end
  end

  it "normalizes ranges, omitted axes, negative indices, stride and empty selections" do
    with_feature_file do |file, _|
      ds = file.create_dataset("matrix", (1..12).to_a, shape: {3, 4})
      ds.read(HDF5.s[-1]).should eq([9, 10, 11, 12])
      ds.read(HDF5.s[1..]).should eq((5..12).to_a)
      ds.read(HDF5.s[..-2, 1]).should eq([2, 6])
      ds.read(HDF5.s[HDF5.slice(0..2, step: 2), HDF5.slice(1..3, step: 2)]).should eq([2, 4, 10, 12])
      HDF5.s[1, 0..2].result_shape(ds.shape).should eq([3_u64])
      ds.read(HDF5.s[1...1]).should be_empty
      ds.write([] of Int32, HDF5.s[1...1])
      ds.write(9, HDF5.s[1...1])
      ds.write(-1, HDF5.s[HDF5.slice(0..2, step: 2), 1..])
      ds.read.should eq([1, -1, -1, -1, 5, 6, 7, 8, 9, -1, -1, -1])
      expect_raises(IndexError) { ds.read(HDF5.s[3]) }
      expect_raises(IndexError) { ds.read(HDF5.s[0, 0, 0]) }
      expect_raises(IndexError) { HDF5.s[:unknown] }
      expect_raises(IndexError) { HDF5.slice(0..2, step: 0) }
      expect_raises(IndexError) { HDF5::Selection.hyperslab({0, 0}, {1}) }
    end
  end

  it "supports selected UTF-8 strings, fixed strings and bounded scalar writes" do
    with_feature_file do |file, _|
      ds = file.create_dataset("labels", ["a", "日本語", "c", "d"], shape: {2, 2}, chunk: :auto)
      ds.read(HDF5.s[HDF5.all, 1]).should eq(["日本語", "d"])
      ds.write(["変更", "updated"], HDF5.s[1])
      ds.write("same", HDF5.s[0])
      ds.read.should eq(["same", "same", "変更", "updated"])
      slice = Slice(String).new(2, "")
      ds.read_into(slice, HDF5.s[1])
      slice.to_a.should eq(["変更", "updated"])
      ds.fill_value.should eq("")
      fixed = file.create_dataset("fixed", ["longvalue", "other"], string_type: HDF5::StringType.fixed(4))
      fixed.read.should eq(["long", "othe"])
      fixed.write(["new"], HDF5.s[1])
      fixed.read.should eq(["long", "new"])
      expect_raises(HDF5::TypeMismatchError) { file.create_dataset("invalid", ["a\0b"]) }
      file.exists?("invalid").should be_false
      expect_raises(HDF5::TypeMismatchError) { file.create_dataset("invalid_ascii", ["日本語"], encoding: :ascii) }
      file.exists?("invalid_ascii").should be_false
      file.attrs["labels"] = ["a", "日本語"]
      file.attrs.get_array("labels", String).should eq(["a", "日本語"])
      file.attrs.modify("labels", ["changed", "変更"])
      file.attrs.get_array("labels", String).should eq(["changed", "変更"])
      expect_raises(HDF5::TypeMismatchError) { file.attrs["labels"] = ["bad\0text"] }
      file.attrs.get_array("labels", String).should eq(["changed", "変更"])
    end
  end

  it "appends on arbitrary axes, preserves fill values and validates maxima" do
    with_feature_file do |file, _|
      ds = file.create_dataset("rows", Int16, shape: {0, 2}, max_shape: {nil, 2}, fill_value: 7)
      ds.chunk.should_not be_nil
      ds.max_shape.should eq([nil, 2_u64])
      ds.append([1_i16, 2_i16, 3_i16, 4_i16], shape: {2, 2})
      ds.append([5_i16, 6_i16], shape: {1, 2})
      ds.append([] of Int16, shape: {0, 2})
      ds.shape.should eq([3_u64, 2_u64])
      ds.resize({4, 2})
      ds.read.should eq([1_i16, 2_i16, 3_i16, 4_i16, 5_i16, 6_i16, 7_i16, 7_i16])
      ds.fill_value.should eq(7_i16)
      expect_raises(HDF5::ShapeMismatchError) { ds.resize({4, 3}) }
      expect_raises(HDF5::ShapeMismatchError) { ds.append([1_i16, 2_i16], shape: {2, 1}) }
      cols = file.create_dataset("cols", [1, 2, 3, 4], shape: {2, 2}, max_shape: {2, nil})
      cols.append([5, 6], shape: {2, 1}, axis: 1)
      cols.read.should eq([1, 2, 5, 3, 4, 6])
      text = file.create_dataset("text", ["a"], max_shape: {nil})
      text.append(["日本語"])
      text.read.should eq(["a", "日本語"])
    end
  end

  it "rolls back failed append and removes a failed new dataset" do
    with_feature_file do |file, _|
      ds = file.create_dataset("values", [1, 2], max_shape: {nil})
      HDF5::Native.fail_write = true
      expect_raises(HDF5::Error) { ds.append([3]) }
      ds.shape.should eq([2_u64])
      HDF5::Native.fail_write = false
      ds.read.should eq([1, 2])
      HDF5::Native.fail_write = true
      expect_raises(HDF5::Error) { file.create_dataset("partial", [1, 2]) }
      file.exists?("partial").should be_false
      HDF5::Native.fail_write = false
    end
  end

  it "yields independent blocks within budget and partial chunks without gaps" do
    with_feature_file do |file, _|
      ds = file.create_dataset("matrix", (1..9).to_a, shape: {3, 3}, chunk: {2, 2})
      blocks = [] of Array(Int32)
      selections = [] of HDF5::Selection
      ds.each_block(max_bytes: 8) do |selection, values|
        (values.size * sizeof(Int32)).should be <= 8
        ds.read(selection).should eq(values)
        blocks << values
        selections << selection
      end
      blocks.sum(&.size).should eq(9)
      blocks.flatten.sort!.should eq((1..9).to_a)
      selections.first.result_shape(ds.shape).should eq([1_u64, 2_u64])
      ds.each_block(max_bytes: Int64::MAX) { |_, b| b.size.should eq(9) }
      chunks = [] of Array(Int32)
      ds.each_chunk { |_, values| chunks << values }
      chunks.should eq([[1, 2, 4, 5], [3, 6], [7, 8], [9]])
      expect_raises(ArgumentError) { ds.each_block(max_bytes: 3) { |_, _| } }
      file.create_dataset("scalar", 42).each_block(max_bytes: 4) { |_, b| b.should eq([42]) }
      count = 0
      file.create_dataset("empty", Int32, shape: {0}).each_block(max_bytes: 4) { |_, _| count += 1 }
      count.should eq(0)
      strings = file.create_dataset("strings", ["a", "b", "c"], chunk: {2})
      expect_raises(HDF5::TypeMismatchError) { strings.each_block(max_bytes: 1024) { |_, _| } }
      string_chunks = [] of Array(String)
      strings.each_chunk { |_, b| string_chunks << b }
      string_chunks.should eq([["a", "b"], ["c"]])
    end
  end

  it "rejects invalid storage settings before linking a dataset" do
    with_feature_file do |file, _|
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("negative", Int32, shape: {-1}) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("fractional", Int32, shape: {1.5}) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("fractional_max", Int32, shape: {1}, max_shape: {1.5}) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("rank", Int32, shape: {2, 2}, chunk: {2}) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("zero", Int32, shape: {2}, chunk: {0}) }
      expect_raises(HDF5::ShapeMismatchError) { file.create_dataset("max", Int32, shape: {2}, max_shape: {1}) }
      expect_raises(ArgumentError) { file.create_dataset("level", Int32, shape: {2}, compression: :gzip, compression_level: 10) }
      expect_raises(ArgumentError) { file.create_dataset("filter", Int32, shape: {2}, compression: :unknown) }
      file.keys.should be_empty
      large = file.create_dataset("large", Float64, shape: {1000, 1000}, chunk: :auto)
      ((large.chunk || raise "Expected chunked storage").product * 8).should be <= 256 * 1024
      file.create_dataset("filters", (1..10).to_a, shuffle: true, fletcher32: true, compression: :gzip).read.should eq((1..10).to_a)
    end
  end

  it "creates and modifies shaped attributes without replacing their type" do
    with_feature_file do |file, _|
      attrs = file.attrs
      attrs.create("matrix", [1_i16, 2_i16, 3_i16, 4_i16], shape: {2, 2})
      attrs.modify("matrix", [5, 6, 7, 8], shape: {2, 2})
      attrs.get_array("matrix", Int16).should eq([5_i16, 6_i16, 7_i16, 8_i16])
      attribute = attrs["matrix"]
      attribute.shape.should eq([2_u64, 2_u64])
      dtype = attribute.datatype
      dtype.size.should eq(2)
      dtype.close
      attribute.close
      expect_raises(HDF5::AlreadyExistsError) { attrs.create("matrix", 42) }
      expect_raises(HDF5::ShapeMismatchError) { attrs.modify("matrix", [1]) }
      expect_raises(HDF5::ShapeMismatchError) { attrs.modify("matrix", [1, 2, 3, 4], shape: {4}) }
      expect_raises(HDF5::ShapeMismatchError) { attrs.get("matrix", Int16) }
      attrs.write("matrix", "replacement")
      attrs.get("matrix", String).should eq("replacement")
      attrs.delete("matrix")
      attrs.has_key?("matrix").should be_false
    end
  end

  it "preserves an attribute when writing or swapping its replacement fails" do
    with_feature_file do |file, _|
      file.attrs["value"] = 7
      HDF5::Native.fail_attribute_write = true
      expect_raises(HDF5::Error) { file.attrs["value"] = "replacement" }
      HDF5::Native.fail_attribute_write = false
      file.attrs.get("value", Int32).should eq(7)
      file.attrs.keys.should eq(["value"])
      HDF5::Native.fail_rename = true
      expect_raises(HDF5::Error) { file.attrs["value"] = "replacement" }
      file.attrs.get("value", Int32).should eq(7)
      file.attrs.keys.should eq(["value"])
    end
  end

  it "moves links and inspects dangling soft and external links" do
    with_feature_file do |file, _|
      file.create_dataset("values", [1, 2]).close
      file.link_info("values").should be_a(HDF5::HardLink)
      file.soft_link("/missing", "soft")
      file.exists?("soft").should be_true
      file.link_info("soft").should eq(HDF5::SoftLink.new("/missing"))
      file.external_link("missing.h5", "/data", "external")
      file.link_info("external").should eq(HDF5::ExternalLink.new("missing.h5", "/data"))
      file.move("values", "nested/moved")
      file.exists?("values").should be_false
      file.dataset("nested/moved", Int32).read.should eq([1, 2])
      expect_raises(HDF5::TypeMismatchError) { file.require_group("nested/moved") }
    end
  end

  it "closes children, metadata and references when their file closes" do
    with_feature_file do |file, _|
      ds = file.create_dataset("values", [1, 2])
      attrs = ds.attrs
      attrs["unit"] = "count"
      attribute = attrs["unit"]
      space = ds.dataspace
      dtype = ds.datatype
      group = file.create_group("group")
      ref = file.reference("values")
      file.close
      file.close
      expect_raises(HDF5::ClosedObjectError) { ds.read }
      expect_raises(HDF5::ClosedObjectError) { attrs.keys }
      expect_raises(HDF5::ClosedObjectError) { attribute.read(String) }
      expect_raises(HDF5::ClosedObjectError) { dtype.size }
      expect_raises(HDF5::ClosedObjectError) { space.dims }
      expect_raises(HDF5::ClosedObjectError) { group.keys }
      expect_raises(HDF5::ClosedObjectError) { ref.target_path }
      ds.close
      attribute.close
      space.close
      dtype.close
      group.close
      ref.close
    end
  end

  it "preserves user exceptions when block cleanup also fails and allows close retry" do
    with_feature_file do |file, _|
      group = file.create_group("group")
      HDF5::Native.fail_close = true
      error = expect_raises(Exception, "user failure") do
        HDF5::Cleanup.with(group) { raise "user failure" }
      end
      error.message.should eq("user failure")
      HDF5::Native.fail_close = false
      group.keys.should be_empty
      group.close
      group.close
    end
  end
  it "reports an append rollback failure with the write failure as its cause" do
    with_feature_file do |file, _|
      ds = file.create_dataset("values", [1, 2], max_shape: {nil})
      HDF5::Native.fail_write = true
      HDF5::Native.extent_calls_until_failure = 1
      error = expect_raises(HDF5::Error, "rollback failed") { ds.append([3]) }
      error.cause.should be_a(HDF5::Error)
      (error.cause || raise "Expected write failure cause").message.should eq("Failed to write dataset")
      HDF5::Native.fail_write = false
      HDF5::Native.extent_calls_until_failure = -1
      ds.shape.should eq([3_u64])
    end
  end

  it "releases the native lock before invoking user callbacks" do
    with_feature_file do |file, _|
      ds = file.create_dataset("values", [1, 2, 3], chunk: {2})
      callback = -> {
        channel = Channel(Array(Int32)).new
        spawn { channel.send(ds.read) }
        select
        when values = channel.receive
          values.should eq([1, 2, 3])
        when timeout(1.second)
          raise "User callback held the native lock"
        end
      }
      ds.each_block(max_bytes: 4) { |_, _| callback.call }
      ds.each_chunk { |_, _| callback.call }
      file.each { |_| callback.call }
      ds.attrs["unit"] = "count"
      ds.attrs.each { |_| callback.call }
      file.create_dataset("array", [1, 2], shape: {1, 2}) { |_| callback.call }
      file.create_dataset("scalar", 7) { |opened| opened.read_scalar.should eq(7); callback.call }
      file.create_dataset("null", HDF5::Empty(Int32).new) { |opened| opened.null?.should be_true; callback.call }
      file.create_dataset("typed_scalar", Int16, 42) { |opened| opened.read_scalar.should eq(42_i16); callback.call }
      file.create_dataset("typed_array", Int64, [1, 2], shape: {1, 2}) { |_| callback.call }
    end
  end

  it "broadcasts scalars using a bounded reusable buffer, including block hyperslabs" do
    with_feature_file do |file, _|
      ds = file.create_dataset("big", Int32, shape: {70000})
      ds.write(7)
      ds.read.all? { |v| v == 7 }.should be_true
      ds = file.create_dataset("blocks", (0..9).to_a)
      selection = HDF5::Selection.hyperslab({1}, {3}, stride: {3}, block: {2})
      ds.write(-1, selection)
      ds.read.should eq([0, -1, -1, 3, -1, -1, 6, -1, -1, 9])
      file.create_dataset("fill_scalar", 7, shape: {2, 2}).read.should eq([7, 7, 7, 7])
      file.create_dataset("explicit_scalar", Int8, 7, casting: HDF5::Casting::Safe).read_scalar.should eq(7_i8)
    end
  end
  it "supports typed options, scalar Bool and complex fill values" do
    with_feature_file do |file, _|
      options = HDF5::DatasetCreateOptions.new(chunk: {2, 2}, max_shape: {nil, 2},
        compression: HDF5::Compression.gzip(1), shuffle: true)
      ds = file.create_dataset("options", Float32, shape: {0, 2}, options: options)
      ds.append([1_f32, 2_f32], shape: {1, 2})
      ds.chunk.should eq([2_u64, 2_u64])
      ds.max_shape.should eq([nil, 2_u64])
      file.create_dataset("bool_scalar", true).read_scalar.should be_true
      z = Complex.new(1, 2)
      complex = file.create_dataset("complex_fill", Complex, shape: {2}, fill_value: z)
      complex.read.should eq([z, z])
      complex.fill_value.should eq(z)
      file.create_dataset("complex_scalar", HDF5::Complex32.new(z)).read_scalar.to_c.should eq(z)
      null = file.create_dataset("null", HDF5::Empty(Bool).new)
      null.read_null.should be_a(HDF5::Empty(Bool))
      expect_raises(HDF5::ShapeMismatchError) { null.write(HDF5::Empty(Bool).new) }
      file.attrs.create("null", HDF5::Empty(Bool).new)
      expect_raises(HDF5::ShapeMismatchError) { file.attrs.modify("null", HDF5::Empty(Bool).new) }
    end
  end

  it "rejects lossy fixed string input when safe casting is requested" do
    with_feature_file do |file, _|
      ds = file.create_dataset("fixed", String, shape: {2}, string_type: HDF5::StringType.fixed(4))
      ds.write(["one", "two"], casting: HDF5::Casting::Safe)
      expect_raises(HDF5::TypeMismatchError) { ds.write(["longvalue", "two"], casting: HDF5::Casting::Safe) }
      expect_raises(HDF5::TypeMismatchError) { ds.write("longvalue", casting: HDF5::Casting::Safe) }
      ds.read.should eq(["one", "two"])
      file.attrs.create("fixed", "one", string_type: HDF5::StringType.fixed(4))
      expect_raises(HDF5::TypeMismatchError) { file.attrs.modify("fixed", "longvalue", casting: HDF5::Casting::Safe) }
      file.attrs.get("fixed", String).should eq("one")
      expect_raises(HDF5::Error) { HDF5::StringType.fixed(0) }
      expect_raises(IndexError) { HDF5::Selection.hyperslab({0.5}, {1}) }
    end
  end

  it "implements exclusive and append file modes without truncating existing content" do
    with_feature_file do |file, path|
      file.create_dataset("value", 42).close
      file.close
      expect_raises(HDF5::FileError) { HDF5.open(path, :x) }
      HDF5.open(path, :a) { |reopened| reopened.dataset("value", Int32).read_scalar.should eq(42) }
      HDF5.open(path, :rw) { |reopened| reopened.dataset("value", Int32).write(43) }
      HDF5.open(path, :r_plus) { |reopened| reopened.dataset("value", Int32).read_scalar.should eq(43) }
    end
  end
  it "checks safe casts and datatype compatibility for empty buffers" do
    with_feature_file do |file, _|
      empty = file.create_dataset("empty", Int16, shape: {0})
      empty.read.should be_empty
      expect_raises(HDF5::TypeMismatchError) { empty.dataset.read(Int8, casting: HDF5::Casting::Safe) }
      expect_raises(HDF5::TypeMismatchError) { empty.write([] of Int64, casting: HDF5::Casting::Safe) }
      expect_raises(HDF5::TypeMismatchError) { empty.dataset.read(String) }
      expect_raises(HDF5::TypeMismatchError) { file.create_dataset("unsafe_small", Int8, 300, casting: HDF5::Casting::Safe) }
      file.exists?("unsafe_small").should be_false
    end
  end
  it "reclaims partially read variable-length values without replacing a read failure" do
    with_feature_file do |file, _|
      strings = file.create_dataset("strings", ["alpha", "日本語"])
      ragged = file.create_dataset("ragged", [[1, 2], [3]])
      file.create_group("target").close
      reference = file.reference("target")
      refs = file.create_dataset("refs", [reference])
      HDF5::Native.fail_read = true
      HDF5::Native.fail_reclaim = true
      expect_raises(HDF5::Error, "Failed to read dataset") { strings.read }
      expect_raises(HDF5::Error, "Failed to read dataset") { ragged.read }
      expect_raises(HDF5::Error, "Failed to read dataset") { refs.read }
      HDF5::Native.fail_read = false
      expect_raises(HDF5::Error, "Failed to reclaim string memory") { strings.read }
      expect_raises(HDF5::Error, "Failed to reclaim variable-length memory") { ragged.read }
      HDF5::Native.fail_reclaim = false
      strings.read.should eq(["alpha", "日本語"])
      ragged.read.should eq([[1, 2], [3]])
      refs.read.first.target_path.should eq("/target")
    end
  end
  it "bounds fixed-length string block payloads by the stored width" do
    with_feature_file do |file, _|
      ds = file.create_dataset("fixed", ["alpha", "beta", "x"], string_type: HDF5::StringType.fixed(5))
      blocks = [] of Array(String)
      ds.each_block(max_bytes: 10) do |_, values|
        values.sum(&.bytesize).should be <= 10
        blocks << values
      end
      blocks.should eq([["alpha", "beta"], ["x"]])
      expect_raises(ArgumentError) { ds.each_block(max_bytes: 4) { |_, _| } }
      expect_raises(HDF5::ShapeMismatchError) do
        file.create_dataset("huge_chunk", Int32, shape: {2}, max_shape: {nil}, chunk: {1_i64 << 60})
      end
      file.exists?("huge_chunk").should be_false
    end
  end
end
