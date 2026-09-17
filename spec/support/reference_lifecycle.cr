require "../../src/hdf5"

LibHDF5.H5open
LibHDF5.H5Eset_auto2(0, nil, nil)
path = ARGV[1]
file = HDF5.open(path, :w)
file.create_group("target").close
source = file.reference("target")
copy = source.dup
source.close
raise "Copy became invalid" unless copy.target_path == "/target"
file.create_dataset("refs", [copy, copy]).close
file.attrs["ref"] = copy
read = file.dataset("refs", HDF5::Reference).read
raise "References changed" unless read.all? { |reference| reference.target_path == "/target" }
attr_ref = file.attrs.get("ref", HDF5::Reference)
raise "Attribute reference changed" unless attr_ref.target_path == "/target"
case ARGV[0]
when "explicit"
  read.each(&.close)
  attr_ref.close
  copy.close
  file.close
when "gc"
  GC.collect
  raise "GC invalidated reference" unless read[0].target_path == "/target"
  file.close
  GC.collect
when "exit"
  # Exit cleanup must close still-live references and handles before HDF5 exits.
else
  raise "Unknown test mode"
end
