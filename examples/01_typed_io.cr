require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_typed_io_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("measurements/signal", [1.0, 2.0, 3.0, 4.0], shape: {2, 2}) do |signal|
      signal.attrs["unit"] = "a.u."
    end
  end
  HDF5.open(path) do |file|
    file.dataset("measurements/signal", Float64) do |signal|
      puts signal.shape.inspect
      puts signal.read(HDF5.s[-1]).inspect
      puts signal.read_scalar(HDF5.s[0, 1]).inspect
      buffer = Slice(Float64).new(2, 0.0)
      signal.read_into(buffer, HDF5.s[HDF5.all, 0])
      puts buffer.inspect
      puts signal.attrs.get("unit", String).inspect
    end
  end
ensure
  File.delete(path) if File.exists?(path)
end
