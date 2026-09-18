# Store a matrix using a flat, row-major Array and an explicit shape.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "03_multidimensional_arrays.h5")

# The matrix has two rows: [1.5, 2.5, 3.5] and [4.5, 5.5, 6.5].
values = [1.5, 2.5, 3.5, 4.5, 5.5, 6.5]
HDF5.open(path, :w) do |file|
  file.create_dataset("matrix", values, shape: {2, 3}) { }
end

HDF5.open(path) do |file|
  file.dataset("matrix", Float64) do |matrix|
    puts "Shape: #{matrix.shape}" # => [2, 3]
    puts "Flat values: #{matrix.read}"
    matrix.read.each_slice(3).with_index do |row, index|
      puts "Row #{index}: #{row}"
    end
  end
end

# Nested numeric arrays describe variable-length elements, not a dense matrix.
# See advanced/05_references_and_vlen.cr for that separate representation.
