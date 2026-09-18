# Distinguish a single value, an empty array, and a Null dataspace.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "07_scalar_empty_null.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("scalar", 1.5) { }                    # One value, shape [].
  file.create_dataset("empty", Float64, shape: {0, 3}) { }  # Zero rows, shape [0, 3].
  file.create_dataset("null", HDF5::Empty(Float64).new) { } # Type only, no values.
end

HDF5.open(path) do |file|
  {"scalar", "empty", "null"}.each do |name|
    file.dataset(name, Float64) do |data|
      puts "#{name}: #{data.space_class}, shape #{data.shape}, size #{data.size}"
      if data.null?
        puts "  Null marker: #{data.read_null.inspect}"
      elsif data.scalar?
        puts "  Scalar value: #{data.read_scalar}; array read: #{data.read}"
      else
        puts "  Empty array: #{data.read}"
      end
    end
  end
end

# Both scalar and Null have shape []; use scalar? / null? to distinguish them.
