require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe "Compression" do
    it "creates a gzip-compressed chunked dataset" do
      data = Array(Float64).new(100, &.to_f64)
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset(
          "compressed",
          Float64,
          shape: {100},
          chunk: {20},
          compression: :gzip,
          compression_level: 4
        ) do |dataset|
          dataset.write(data)
        end
      end
      HDF5.open(TMP_FILE, :r) do |file|
        result = file.dataset("compressed", Float64).read
        result.size.should eq(100)
        result[50].should be_close(50.0, 1e-12)
      end
    end

    it "accepts HDF5::Compression.gzip object" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.create_dataset(
          "ds",
          Int32,
          shape: {50},
          chunk: {10},
          compression: HDF5::Compression.gzip(level: 3)
        ) do |dataset|
          dataset.write(Array(Int32).new(50) { |idx| idx })
        end
      end
      HDF5.open(TMP_FILE, :r) do |file|
        file.dataset("ds", Int32).read[25].should eq(25)
      end
    end
  end
end
