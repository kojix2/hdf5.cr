# Read selected rows, columns, and strided regions without reading all values.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "08_reading_slices.h5")

# Four rows: [0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15].
HDF5.open(path, :w) do |file|
  file.create_dataset("matrix", (0...16).to_a, shape: {4, 4}) { }
end

HDF5.open(path) do |file|
  file.dataset("matrix", Int32) do |matrix|
    puts "Row 1: #{matrix.read(HDF5.s[1, HDF5.all])}"        # => [4, 5, 6, 7]
    puts "Last column: #{matrix.read(HDF5.s[HDF5.all, -1])}" # => [3, 7, 11, 15]
    puts "One value: #{matrix.read_scalar(HDF5.s[2, 3])}"    # => 11

    every_other_row = HDF5.s[HDF5.slice(0...4, step: 2), HDF5.all]
    puts "Every other row: #{matrix[every_other_row]}"
    puts "Selected shape: #{every_other_row.result_shape(matrix.shape)}" # => [2, 4]
  end
end

# Indices are zero-based; -1 is the last element. Integer selectors drop an axis.
# read always returns a flat array; read_scalar returns a single selected value.
