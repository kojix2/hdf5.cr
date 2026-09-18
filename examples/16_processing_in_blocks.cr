# Compute a total while reading only a small block of values at a time.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "16_processing_in_blocks.h5")

HDF5.open(path, :w) do |file|
  file.create_dataset("samples", (0...48).map(&.to_i16), shape: {12, 4}) { }
end

HDF5.open(path) do |file|
  file.dataset("samples", Int16) do |samples|
    total = 0_i64
    # 32 bytes / sizeof(Int16) = at most 16 elements (four rows) per block.
    samples.each_block(max_bytes: 32) do |selection, values|
      puts "Block shape: #{selection.result_shape(samples.shape)}, values: #{values}"
      total += values.sum(0_i64)
    end
    puts "Sum: #{total}" # => 1128
  end
end

# The budget covers element payload, not total process memory or HDF5 caches.
# Variable-length strings and arrays cannot use this byte limit; use each_chunk.
