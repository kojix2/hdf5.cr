require "../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_links_#{Process.pid}.h5")
source_path = File.join(Dir.tempdir, "hdf5_link_source_#{Process.pid}.h5")
begin
  HDF5.open(source_path, :w) do |file|
    file.create_dataset("shared", [7, 8, 9]).close
  end
  HDF5.open(path, :x) do |file|
    file.require_group("runs/day_1").close
    file.create_dataset("runs/day_1/signal", [1, 2, 3]).close
    file.link("runs/day_1/signal", "signal_alias")
    file.soft_link("/runs/day_1/signal", "latest")
    file.external_link(source_path, "/shared", "shared")

    # Link information is a union of typed hard, soft and external values.
    {"signal_alias", "latest", "shared"}.each do |name|
      case info = file.link_info(name)
      when HDF5::HardLink
        puts "#{name}: hard link"
      when HDF5::SoftLink
        puts "#{name}: soft link to #{info.target}"
      when HDF5::ExternalLink
        puts "#{name}: external link to #{info.filename}:#{info.path}"
      end
    end
    file.dataset("shared", Int32) { |data| puts "External data: #{data.read}" }

    file.move("runs/day_1/signal", "archive/signal")
    file.delete("archive/signal")
    # A hard link keeps the object alive; a soft link retains its original path.
    file.dataset("signal_alias", Int32) { |data| puts "Hard-linked data: #{data.read}" }
    puts "Dangling soft link: #{file.link_info("latest").inspect}"
    puts "Original target exists? #{file.exists?("runs/day_1/signal")}"
    puts "Root entries: #{file.keys}"
    file.open_object("runs") do |object|
      case object
      when HDF5::Group
        puts "Run groups: #{object.keys}"
      when HDF5::Dataset
        puts "Dataset shape: #{object.shape}"
      end
    end
  end
ensure
  File.delete(path) if File.exists?(path)
  File.delete(source_path) if File.exists?(source_path)
end
