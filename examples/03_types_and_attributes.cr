require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_types_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("bits", [false, true]).close
    file.create_dataset("complex", [HDF5::Complex32.new(1, 2)]).close
    file.create_dataset("null", HDF5::Empty(Int16).new).close
    file.create_dataset("labels", ["alpha", "日本語"]) do |labels|
      puts labels.read(HDF5.s[1..]).inspect
      labels.write("updated", HDF5.s[0])
      puts labels.read.inspect
    end
    file.attrs.create("scale", Int16, 2, casting: HDF5::Casting::Safe)
    file.attrs.modify("scale", 4, casting: HDF5::Casting::Safe)
    puts file.attrs.get("scale", Int16).inspect
    file.attrs.create("matrix", [1, 2, 3, 4], shape: {2, 2})
    puts file.attrs.get_array("matrix", Int32).inspect
    file.soft_link("/labels", "latest")
    file.move("labels", "names")
    puts file.link_info("latest").inspect # still records /labels, even after moving its target
    puts file.dataset("complex", HDF5::Complex32).read.first.to_c.inspect
    puts file.dataset("null", Int16).read_null.inspect
  end
ensure
  File.delete(path) if File.exists?(path)
end
