# Visit regions matching the dataset's storage chunks, including a partial edge.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "17_processing_chunks.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("samples", (0...15).to_a, shape: {5, 3}, chunk: {2, 3}) { }
end

HDF5.open(path) do |file|
  file.dataset("samples", Int32) do |samples|
    puts "Configured chunk shape: #{samples.chunk}"
    total = 0
    samples.each_chunk do |selection, values|
      puts "Chunk region: #{selection.result_shape(samples.shape)}, values: #{values}"
      total += values.sum
    end
    puts "Sum: #{total}" # => 105
  end
end

# Region shapes are [2, 3], [2, 3], and [1, 3]; the final region is clipped.
# Unlike each_block, each_chunk follows storage layout instead of a byte budget.
