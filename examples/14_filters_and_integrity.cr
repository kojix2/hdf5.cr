# Combine gzip compression, byte shuffling, and Fletcher32 checksums.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "14_filters_and_integrity.h5")
values = Array(Int32).new(4096) { |index| index % 16 }

HDF5.open(path, :w) do |file|
  file.create_dataset("plain", values, chunk: {1024}) { }
  # Shuffle groups similar bytes for compression; Fletcher32 detects corruption.
  # This example requires an HDF5 build with gzip support.
  file.create_dataset("filtered", values, chunk: {1024},
    compression: :gzip, compression_level: 6, shuffle: true, fletcher32: true) { }
end

HDF5.open(path) do |file|
  {"plain", "filtered"}.each do |name|
    file.dataset(name, Int32) do |data|
      puts "#{name}: #{data.storage_size} stored dataset bytes"
      puts "#{name}: values match original? #{data.read == values}"
    end
  end
end

# Stored byte counts exclude file metadata and depend on the data and library.
