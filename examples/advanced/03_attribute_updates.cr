# Compare attribute creation, replacement, and in-place updates after tutorial 05.
require "../../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_attributes_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    attributes = file.attrs
    attributes.create("version", Int16, 1, casting: HDF5::Casting::Safe)
    attributes.create("calibration", [1.0, 0.0, 0.0, 1.0], shape: {2, 2})
    attributes.create("missing", HDF5::Empty(Float64).new)

    # create refuses an existing name.
    begin
      attributes.create("version", 2)
    rescue error : HDF5::AlreadyExistsError
      puts "Duplicate creation rejected: #{error.message}"
    end

    # modify retains the stored datatype and shape.
    attributes.modify("version", 2_i64, casting: HDF5::Casting::Safe)
    attributes.modify("calibration", [2.0, 0.0, 0.0, 2.0], shape: {2, 2})
    attributes.each do |entry|
      name, attribute = entry
      puts "#{name}: shape #{attribute.shape}, dataspace #{attribute.space_class}"
    end # Attribute handles supplied to each are automatically closed.

    # write (also []=) creates or replaces, and can change the type and shape.
    attributes.write("version", "revision 2")
    attributes["title"] = "Calibration example"
    puts "Replaced version: #{attributes.get("version", String)}"
    puts "Calibration: #{attributes.get_array("calibration", Float64)}"
    puts "Null attribute: #{attributes.get_null("missing", Float64).inspect}"
    puts "Optional attribute: #{attributes.get?("author", String).inspect}"

    # Invalid replacement input is rejected without losing the old value.
    begin
      attributes.write("version", "invalid\0text")
    rescue error : HDF5::Error
      puts "Replacement rejected: #{error.message}"
    end
    puts "Version still present: #{attributes.get("version", String)}"
    attributes.delete("title")
  end
ensure
  File.delete(path) if File.exists?(path)
end
