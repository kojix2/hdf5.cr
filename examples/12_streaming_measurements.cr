require "../src/hdf5"

# A small end-to-end acquisition example: append batches, scan bounded blocks,
# save per-channel statistics, then reopen without loading the entire dataset.
path = File.join(Dir.tempdir, "hdf5_streaming_#{Process.pid}.h5")
channels = 3
batch_rows = 4
begin
  HDF5.open(path, :w) do |file|
    file.attrs["experiment"] = "Three-channel acquisition"
    file.create_dataset("run/samples", Float32, shape: {0, channels},
      max_shape: {nil, channels}, chunk: {5, channels}, compression: :gzip) do |samples|
      samples.attrs.create("channel_names", ["A", "B", "C"])
      samples.attrs["unit"] = "V"
      3.times do |batch|
        values = Array(Float32).new(batch_rows * channels) do |index|
          sample = batch * batch_rows + index // channels
          channel = index % channels
          (sample * (channel + 1)).to_f32
        end
        samples.append(values, shape: {batch_rows, channels})
      end
      file.flush

      sums = Array(Float64).new(channels, 0.0)
      # At most 3 rows * 3 channels * sizeof(Float32) = 36 bytes per read.
      samples.each_block(max_bytes: 36) do |selection, values|
        puts "Processing block #{selection.result_shape(samples.shape)}, #{values.size * sizeof(Float32)} bytes"
        values.each_slice(channels) do |row|
          row.each_with_index { |value, channel| sums[channel] += value }
        end
      end
      means = sums.map { |sum| sum / samples.shape[0] }
      samples.attrs.create("channel_means", means)
      puts "Saved means: #{means}"
      samples.each_chunk { |selection, _| puts "Physical chunk region: #{selection.result_shape(samples.shape)}" }
    end
  end

  HDF5.open(path) do |file|
    file.dataset("run/samples", Float32) do |samples|
      puts "Experiment: #{file.attrs.get("experiment", String)}"
      puts "Channels: #{samples.attrs.get_array("channel_names", String)}"
      puts "Means: #{samples.attrs.get_array("channel_means", Float64)}"
      puts "Last observation: #{samples.read(HDF5.s[-1])}"
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
