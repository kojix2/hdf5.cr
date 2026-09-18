# Inspect shape and stored datatype without loading the dataset's values.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "04_dataset_metadata.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("samples", Int16, shape: {4, 3}) { }
end

HDF5.open(path) do |file|
  file.dataset("samples", Int16) do |samples|
    puts "Shape: #{samples.shape}"                    # => [4, 3]
    puts "Rank (number of axes): #{samples.rank}"     # => 2
    puts "Size (number of elements): #{samples.size}" # => 12

    # datatype returns an owned handle; close it when finished.
    dtype = samples.datatype
    begin
      puts "Type class: #{dtype.type_class}"
      puts "Bytes per element: #{dtype.size}"
      puts "Byte order: #{dtype.byte_order}"
      puts "Precision in bits: #{dtype.precision}"
    ensure
      dtype.close
    end
  end
end
