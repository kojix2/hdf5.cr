# Choose how a dataset is divided into storage chunks.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "13_chunked_storage.h5")
values = (0...24).to_a

HDF5.open(path, :w) do |file|
  file.create_dataset("contiguous", values, shape: {6, 4}) { }
  # Each chunk holds two complete rows. Filters and resizing require chunking.
  file.create_dataset("chunked", values, shape: {6, 4}, chunk: {2, 4}) { }
  file.create_dataset("automatic", values, shape: {6, 4}, chunk: :auto) { }
end

HDF5.open(path) do |file|
  {"contiguous", "chunked", "automatic"}.each do |name|
    file.dataset(name, Int32) do |data|
      puts "#{name}: shape #{data.shape}, chunk #{data.chunk.inspect}"
    end
  end
end

# A nil chunk means contiguous storage. Automatic chunks target 256 KiB.
# The best chunk shape depends on which regions you read and write most often.
