require "./spec_helper"

describe HDF5 do
  after_each do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
    File.delete(EXT_FILE) if File.exists?(EXT_FILE)
  end

  describe "round-trip with nested groups and datasets" do
    it "writes and reads nested structure" do
      HDF5.open(TMP_FILE, :w) do |file|
        file.attrs["title"] = "RNA-seq"

        file.require_group("samples/S1") do |sample|
          sample["genes"] = ["TP53", "CTNNB1", "TERT"]
          sample["vaf"] = [0.42, 0.31, 0.18]
          sample.attrs["units"] = "SI"
        end
      end

      HDF5.open(TMP_FILE, :r) do |file|
        file.attrs.get("title", String).should eq("RNA-seq")

        genes = file.dataset("samples/S1/genes", String).read
        genes.should eq(["TP53", "CTNNB1", "TERT"])

        vaf = file.dataset("samples/S1/vaf", Float64).read
        vaf[0].should be_close(0.42, 1e-12)

        file.open_group("samples/S1") do |sample|
          sample.attrs.get("units", String).should eq("SI")
        end
      end
    end
  end
end
