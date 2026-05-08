module HDF5
  class TypedDataset(T)
    def initialize(@dataset : Dataset)
    end

    def shape : Array(UInt64)
      @dataset.shape
    end

    def rank : Int32
      @dataset.rank
    end

    def size : UInt64
      @dataset.size
    end

    def datatype : Datatype
      @dataset.datatype
    end

    def dataspace : Dataspace
      @dataset.dataspace
    end

    def storage_size : UInt64
      @dataset.storage_size
    end

    def attrs : Attributes
      @dataset.attrs
    end

    def read : Array(T)
      {% if T == String %}
        @dataset.read_strings
      {% else %}
        @dataset.read(T)
      {% end %}
    end

    def read(selection : Selection) : Array(T)
      {% if T == String %}
        raise Error.new("Partial string I/O not supported")
      {% else %}
        @dataset.read(T, selection)
      {% end %}
    end

    def read_to(buffer : Slice(T)) : Nil
      @dataset.read_to(buffer.to_unsafe, T)
    end

    def write(data : Array(T)) : Nil
      {% if T == String %}
        @dataset.write_strings(data)
      {% else %}
        @dataset.write(data)
      {% end %}
    end

    def write(data : Slice(T)) : Nil
      {% if T == String %}
        raise Error.new("Slice write not supported for String datasets")
      {% else %}
        @dataset.write(data)
      {% end %}
    end

    def write(data : Array(T), selection : Selection) : Nil
      {% if T == String %}
        raise Error.new("Partial string I/O not supported")
      {% else %}
        @dataset.write(data, selection)
      {% end %}
    end

    def resize(new_shape : Indexable) : Nil
      @dataset.resize(new_shape)
    end

    def [](selection : Selection) : Array(T)
      read(selection)
    end

    def []=(selection : Selection, data : Array(T)) : Nil
      write(data, selection)
    end

    def close : Nil
      @dataset.close
    end

    def finalize
      # Dataset finalizer handles cleanup
    end
  end
end
