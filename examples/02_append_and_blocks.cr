require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_append_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("samples", Float32, shape: {0, 2}, max_shape: {nil, 2},
      chunk: {256, 2}, compression: :gzip, fill_value: 0.0_f32) do |samples|
      samples.append([1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32], shape: {2, 2})
      samples.append([5.0_f32, 6.0_f32], shape: {1, 2})
      total = 0.0
      samples.each_block(max_bytes: 8) { |_, values| total += values.sum }
      puts total.inspect
      puts samples.max_shape.inspect
      puts samples.chunk.inspect
      samples.each_chunk { |selection, values| puts({selection.result_shape(samples.shape), values}.inspect) }
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
