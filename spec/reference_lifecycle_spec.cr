require "./spec_helper"

describe "native reference lifecycle" do
  it "exits normally after explicit close, GC and implicit process cleanup" do
    binary = File.join(Dir.tempdir, "hdf5_reference_worker_#{Process.pid}")
    path = File.join(Dir.tempdir, "hdf5_reference_worker_#{Process.pid}.h5")
    output = IO::Memory.new
    source = File.join(__DIR__, "support", "reference_lifecycle.cr")
    begin
      result = Process.run("crystal", ["build", source, "-o", binary], output: output, error: output)
      raise "Reference worker did not compile: #{output}" unless result.success?
      {"explicit", "gc", "exit"}.each do |mode|
        output.clear
        result = Process.run(binary, [mode, path], output: output, error: output)
        raise "Reference #{mode} worker failed (#{result.system_exit_status}): #{output}" unless result.success?
      end
    ensure
      File.delete(path) if File.exists?(path)
      File.delete(binary) if File.exists?(binary)
    end
  end
end
