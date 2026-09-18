# Start with zero rows, append batches, and explicitly resize a dataset.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "15_growing_datasets.h5")

HDF5.open(path, :w) do |file|
  # nil in max_shape means unlimited. The second axis stays at two columns.
  file.create_dataset("samples", Float32, shape: {0, 2},
    max_shape: {nil, 2}, chunk: {4, 2}, fill_value: -1.0_f32) do |samples|
    puts "Initial shape: #{samples.shape}"
    samples.append([1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32], shape: {2, 2})
    samples.append([5.0_f32, 6.0_f32], shape: {1, 2})
    puts "After appending: #{samples.shape}, values #{samples.read}"

    samples.resize({4, 2})
    puts "New row uses the fill value: #{samples.read(HDF5.s[-1])}"
    samples.write([7.0_f32, 8.0_f32], HDF5.s[-1])
    puts "After writing the new row: #{samples.read(HDF5.s[-1])}"
    puts "Maximum shape: #{samples.max_shape}"
  end
end

# append defaults to axis 0. Multidimensional batches need their own shape.
