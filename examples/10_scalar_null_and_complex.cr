require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_spaces_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("scalar", 1.5).close                    # shape [], one element
    file.create_dataset("null", HDF5::Empty(Float64).new).close # no elements or dimensions
    file.create_dataset("empty", Float64, shape: {0, 3}).close  # zero rows, rank 2
    file.create_dataset("enabled", true).close                  # FALSE/TRUE enum, h5py-compatible
    file.create_dataset("complex64", [HDF5::Complex32.new(1, 2), HDF5::Complex32.new(3, -4)]).close
    file.create_dataset("complex128", [Complex.new(1, 2), Complex.new(3, -4)]).close
  end

  HDF5.open(path) do |file|
    {"scalar", "null", "empty"}.each do |name|
      file.dataset(name, Float64) do |data|
        puts "#{name}: #{data.space_class}, shape #{data.shape}, rank #{data.rank}, size #{data.size}"
        if data.null?
          puts "  Typed Null marker: #{data.read_null.inspect}"
        elsif data.scalar?
          puts "  Scalar: #{data.read_scalar}; flat read: #{data.read}"
        else
          puts "  Empty array: #{data.read}"
        end
      end
    end
    file.dataset("enabled", Bool) { |data| puts "Bool scalar: #{data.read_scalar}" }
    file.dataset("complex64", HDF5::Complex32) do |data|
      values = data.read.map(&.to_c) # Explicit conversion to standard Complex.
      puts "complex64 converted to Complex: #{values}"
      puts "Explicit conversion back: #{HDF5::Complex32.new(values.first).inspect}"
    end
    file.dataset("complex128", Complex) { |data| puts "complex128: #{data.read}" }
  end
ensure
  File.delete(path) if File.exists?(path)
end
