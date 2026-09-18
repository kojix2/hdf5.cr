# Store object references and ragged numeric arrays; close owned reference handles.
require "../../src/hdf5"

path = File.join(Dir.tempdir, "hdf5_references_#{Process.pid}.h5")
begin
  HDF5.open(path, :w) do |file|
    file.create_dataset("target", [10, 20, 30]).close
    reference = file.reference("target")
    copy = reference.dup # Independent native ownership through H5Rcopy.
    begin
      reference.close
      file.create_dataset("references", [copy, copy]).close
      file.attrs["primary"] = copy
      puts "Copy remains usable after closing the original: #{copy.target_path}"
    ensure
      copy.close
      reference.close # Explicit close is idempotent.
    end

    # Nested numeric arrays represent variable-length elements, not a dense matrix.
    file.create_dataset("events", [[1, 2], [] of Int32, [3, 4, 5]], chunk: {2}) do |events|
      puts "Vlen outer shape: #{events.shape}, values: #{events.read}"
      events.write([[8, 9]], HDF5.s[1])
      events.each_chunk { |_, values| puts "Vlen chunk: #{values}" }
    end
    file.attrs.create("event_groups", [[1], [2, 3]])
  end

  HDF5.open(path) do |file|
    file.dataset("references", HDF5::Reference) do |data|
      references = data.read
      begin
        references.each do |reference|
          object = reference.open
          begin
            case object
            when HDF5::Dataset
              puts "Referenced #{reference.target_path}: #{object.read(Int32)}"
            when HDF5::Group
              puts "Referenced group entries: #{object.keys}"
            end
          ensure
            object.close
          end
        end
      ensure
        references.each(&.close)
      end
    end
    reference = file.attrs.get("primary", HDF5::Reference)
    begin
      puts "Reference attribute: #{reference.target_path}"
    ensure
      reference.close
    end
    puts "Vlen attribute: #{file.attrs.get_array("event_groups", Array(Int32))}"
  end
ensure
  File.delete(path) if File.exists?(path)
end
