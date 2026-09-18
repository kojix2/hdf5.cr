# Update a region of an existing dataset, or fill a selection with one value.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "09_writing_slices.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("matrix", (0...12).to_a, shape: {3, 4}) { }
end

# :r_plus opens an existing file for reading and writing.
HDF5.open(path, :r_plus) do |file|
  file.dataset("matrix", Int32) do |matrix|
    puts "Before: #{matrix.read}"
    matrix[HDF5.s[1, HDF5.all]] = [100, 101, 102, 103]
    puts "Updated row 1: #{matrix.read(HDF5.s[1])}"

    # A scalar fills the selection; arrays must match its element count.
    matrix.write(-1, HDF5.s[HDF5.all, 0])
    puts "After filling column 0: #{matrix.read}"
    # => [-1, 1, 2, 3, -1, 101, 102, 103, -1, 9, 10, 11]
  end
end
