# Refer to data with hard links, path-based soft links, and links to another file.
require "../src/hdf5"

output_dir = File.join(__DIR__, "output")
Dir.mkdir_p(output_dir)
path = File.join(output_dir, "19_links.h5")
source_path = File.join(output_dir, "19_links_source.h5")

HDF5.open(source_path, :w) do |file|
  file.create_dataset("shared", [7, 8, 9]) { }
end
HDF5.open(path, :w) do |file|
  file.create_dataset("signal", [1, 2, 3]) { }
  file.link("signal", "signal_alias")
  file.soft_link("/signal", "latest")
  # Relative external filenames are resolved from the containing HDF5 file.
  file.external_link(File.basename(source_path), "/shared", "shared")

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
  file.dataset("shared", Int32) { |shared| puts "External values: #{shared.read}" }

  file.delete("signal")
  file.dataset("signal_alias", Int32) { |data| puts "Hard link still reads: #{data.read}" }
  puts "Dangling soft link: #{file.link_info("latest").inspect}"
end

# A hard link keeps the object alive; a soft link only retains the original path.
# Keep both generated files together for the external link to remain usable.
