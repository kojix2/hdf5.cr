module HDF5
  class Compression
    enum Filter
      None
      GZip
    end

    getter filter : Filter
    getter level : Int32

    def initialize(@filter : Filter, @level : Int32 = 1)
    end

    def self.gzip(level : Int32 = 6) : Compression
      new(Filter::GZip, level)
    end

    def self.none : Compression
      new(Filter::None, 0)
    end

    def none? : Bool
      @filter == Filter::None
    end
  end
end
