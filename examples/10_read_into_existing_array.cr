# Reuse a Slice as the destination for multiple reads.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "10_read_into_existing_array.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("matrix", (0...12).to_a, shape: {3, 4}) { }
end

HDF5.open(path) do |file|
  file.dataset("matrix", Int32) do |matrix|
    # The buffer must have exactly as many elements as the selected region.
    buffer = Slice(Int32).new(4, 0)
    matrix.read_into(buffer, HDF5.s[0])
    puts "First row: #{buffer.to_a}" # => [0, 1, 2, 3]

    matrix.read_into(buffer, HDF5.s[-1])
    puts "Last row in the same buffer: #{buffer.to_a}" # => [8, 9, 10, 11]
  end
end
