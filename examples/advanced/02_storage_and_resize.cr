# Combine automatic chunking, fill values, and column-wise appends after tutorial 15.
require "../../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_storage_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    # Filters and an extendible maximum shape also enable automatic chunking.
    file.create_dataset("measurements", [10_i16, 20_i16, 30_i16, 40_i16],
      shape: {2, 2}, max_shape: {4, nil}, chunk: :auto, compression: :gzip,
      compression_level: 6, shuffle: true, fletcher32: true, fill_value: -1_i16) do |data|
      data.resize({3, 2})
      puts "New row contains the fill value: #{data.read(HDF5.s[-1])}"
      data.write([50_i16, 60_i16], HDF5.s[-1])

      # Append columns instead of rows; all other dimensions must match.
      data.append([70_i16, 80_i16, 90_i16], shape: {3, 1}, axis: 1)
      puts "After column append: #{data.read} (shape #{data.shape})"
      puts "Chunk: #{data.chunk}, maximum shape: #{data.max_shape}, fill: #{data.fill_value}"
    end
  end

  # Storage metadata survives closing and reopening the file.
  HDF5.open(path, :r_plus) do |file|
    file.dataset("measurements", Int16) do |data|
      puts "Reopened: shape #{data.shape}, chunk #{data.chunk}, maximum #{data.max_shape}"
      begin
        data.resize({5, 3})
      rescue error : HDF5::ShapeMismatchError
        puts "Maximum row count enforced: #{error.message}"
      end
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
