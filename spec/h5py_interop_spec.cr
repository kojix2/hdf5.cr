require "./spec_helper"

private def python_interop(code : String, path : String) : Nil
  python = ENV["H5PY_PYTHON"]? || "python3"
  errors = IO::Memory.new
  status = Process.run(python, ["-c", code, path], output: errors, error: errors)
  raise "Python interoperability check failed: #{errors}" unless status.success?
end

private def with_interop_path(&block : String ->) : Nil
  path = File.join(Dir.tempdir, "hdf5_interop_#{Process.pid}_#{Random::Secure.hex(8)}.h5")
  begin
    block.call(path)
  ensure
    File.delete(path) if File.exists?(path)
  end
end

describe "h5py interoperability" do
  if ENV["H5PY_PYTHON"]?
    it "reads h5py numeric, Bool, complex, UTF-8, Null and both byte orders" do
      with_interop_path do |path|
        python_interop(<<-PY, path)
          import h5py, numpy as np, sys
          with h5py.File(sys.argv[1], 'w') as f:
              for dtype in ['i1','u1','i2','u2','i4','u4','i8','u8','f4','f8','c8','c16']:
                  for endian in ['<','>']:
                      values = [1+2j,3+4j] if dtype[0] == 'c' else [1,2]
                      f.create_dataset(dtype+endian, data=np.array(values,dtype=endian+dtype))
              f['bool'] = np.array([[False,True],[True,False]],dtype=np.bool_)
              f['scalar'] = np.float32(1.5)
              f.create_dataset('empty',shape=(0,3),dtype='i2')
              f['null'] = h5py.Empty('i2')
              f['null_text'] = h5py.Empty(h5py.string_dtype('utf-8'))
              f.create_dataset('text',data=['alpha','日本語'],dtype=h5py.string_dtype('utf-8'))
              f.create_dataset('fixed',data=np.array([b'alpha',b'beta'],dtype='S5'))
              f['bool'].attrs['bools'] = np.array([True,False],dtype=np.bool_)
              f.attrs['complex'] = np.array([1+2j,3+4j],dtype='>c16')
              f.attrs['text'] = ['alpha','日本語']
              f.attrs['null'] = h5py.Empty('i2')
              f['external'] = h5py.ExternalLink('missing.h5','/data')
          PY
        HDF5.open(path) do |file|
          {% for type, name in {Int8: "i1", UInt8: "u1", Int16: "i2", UInt16: "u2", Int32: "i4", UInt32: "u4", Int64: "i8", UInt64: "u8", Float32: "f4", Float64: "f8"} %}
            {"<", ">"}.each do |endian|
              ds = file.dataset({{ name }} + endian, {{ type.id }})
              ds.read.should eq([{{ type.id }}.new(1), {{ type.id }}.new(2)])
              dtype = ds.datatype
              dtype.precision.should eq(sizeof({{ type.id }}) * 8)
              dtype.offset.should eq(0)
              if sizeof({{ type.id }}) > 1
                dtype.byte_order.should eq(endian == "<" ? LibHDF5::ByteOrder::Little : LibHDF5::ByteOrder::Big)
              end
              dtype.close
            end
          {% end %}
          {"<", ">"}.each do |endian|
            file.dataset("c8" + endian, HDF5::Complex32).read.map(&.to_c).should eq([Complex.new(1, 2), Complex.new(3, 4)])
            ds = file.dataset("c16" + endian, Complex)
            ds.read.should eq([Complex.new(1, 2), Complex.new(3, 4)])
            dtype = ds.datatype
            dtype.byte_order.should eq(endian == "<" ? LibHDF5::ByteOrder::Little : LibHDF5::ByteOrder::Big)
            dtype.close
          end
          file.dataset("bool", Bool).read.should eq([false, true, true, false])
          file.dataset("bool", Bool).attrs.get_array("bools", Bool).should eq([true, false])
          file.dataset("scalar", Float32).read_scalar.should eq(1.5_f32)
          file.dataset("empty", Int16).shape.should eq([0_u64, 3_u64])
          file.dataset("null", Int16).read_null.should be_a(HDF5::Empty(Int16))
          file.dataset("null_text", String).read_null.should be_a(HDF5::Empty(String))
          file.dataset("text", String).read(HDF5.s[1..]).should eq(["日本語"])
          file.dataset("fixed", String).read.should eq(["alpha", "beta"])
          file.attrs.get_array("complex", Complex).should eq([Complex.new(1, 2), Complex.new(3, 4)])
          file.attrs.get_array("text", String).should eq(["alpha", "日本語"])
          file.attrs.get_null("null", Int16).should be_a(HDF5::Empty(Int16))
          file.link_info("external").should eq(HDF5::ExternalLink.new("missing.h5", "/data"))
        end
      end
    end

    it "writes interoperable typed data, shaped attributes and storage metadata" do
      with_interop_path do |path|
        HDF5.open(path, :w) do |file|
          ds = file.create_dataset("matrix", [1_i16, 2_i16, 3_i16, 4_i16], shape: {2, 2},
            chunk: {1, 2}, max_shape: {nil, 2}, compression: :gzip, shuffle: true, fletcher32: true, fill_value: 7)
          ds.append([5_i16, 6_i16], shape: {1, 2})
          ds.attrs.create("scale", 1_i64 << 40)
          file.create_dataset("bool", [false, true], fill_value: true).close
          file.create_dataset("c8", [HDF5::Complex32.new(1, 2), HDF5::Complex32.new(3, 4)]).close
          file.create_dataset("c16", [Complex.new(1, 2), Complex.new(3, 4)]).close
          file.create_dataset("scalar", "日本語").close
          file.create_dataset("text", ["alpha", "日本語"]).close
          file.create_dataset("empty", String, shape: {0, 3}).close
          file.create_dataset("null", HDF5::Empty(Int16).new).close
          file.create_dataset("null_text", HDF5::Empty(String).new).close
          file.attrs.create("bools", [true, false], shape: {1, 2})
          file.attrs.create("complex", [Complex.new(1, 2), Complex.new(3, 4)], shape: {2, 1})
          file.attrs.create("text", ["alpha", "日本語"], shape: {1, 2})
          file.attrs.create("null", HDF5::Empty(Int16).new)
        end
        python_interop(<<-PY, path)
          import h5py, numpy as np, sys
          with h5py.File(sys.argv[1], 'r') as f:
              d = f['matrix']
              assert d.dtype == np.dtype('<i2')
              assert d.shape == (3,2) and d.maxshape == (None,2)
              assert d.chunks == (1,2)
              assert d.compression == 'gzip' and d.shuffle and d.fletcher32
              assert d.fillvalue == 7
              assert np.array_equal(d[:],[[1,2],[3,4],[5,6]])
              assert d.attrs['scale'] == 2**40
              assert f['bool'].dtype == np.dtype(np.bool_)
              assert np.array_equal(f['bool'][:],[False,True])
              assert f['bool'].fillvalue == True
              for name in ['c8','c16']:
                  assert f[name].dtype == np.dtype('<'+name)
                  assert np.array_equal(f[name][:],[1+2j,3+4j])
              assert f['scalar'].shape == () and f['scalar'].asstr()[()] == '日本語'
              assert list(f['text'].asstr()[:]) == ['alpha','日本語']
              assert f['empty'].shape == (0,3)
              assert isinstance(f['null'][()],h5py.Empty) and f['null'].dtype == np.dtype('<i2')
              assert isinstance(f['null_text'][()],h5py.Empty)
              assert f.attrs['bools'].shape == (1,2)
              assert f.attrs['complex'].shape == (2,1)
              assert f.attrs['text'].shape == (1,2)
              assert isinstance(f.attrs['null'],h5py.Empty)
          PY
      end
    end
  else
    pending "set H5PY_PYTHON to enable bidirectional h5py interoperability checks" do
    end
  end
end
