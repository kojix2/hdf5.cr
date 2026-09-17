module HDF5
  class TypedDataset(T)
    getter dataset : Dataset

    def initialize(@dataset : Dataset)
    end

    delegate shape, rank, size, datatype, dataspace, storage_size, attrs, resize,
      chunk, max_shape, space_class, null?, scalar?, closed?, close, to: @dataset

    def read(selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Array(T)
      dataset.read(T, selection, casting: casting)
    end

    def read_scalar(selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : T
      dataset.read_scalar(T, selection, casting: casting)
    end

    def read_null : Empty(T)
      dataset.read_null(T)
    end

    def read_into(buffer : Slice(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil
      dataset.read_into(buffer, selection, casting: casting)
    end

    def read_to(buffer : Slice(T), selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil
      read_into(buffer, selection, casting: casting)
    end

    def write(data, selection : Selection? = nil, *, casting : Casting = Casting::Unsafe) : Nil
      dataset.write(data, selection, casting: casting)
    end

    def append(data, *, shape : Indexable? = nil, axis : Int = 0, casting : Casting = Casting::Unsafe) : Nil
      dataset.append(data, shape: shape, axis: axis, casting: casting)
    end

    def fill_value(*, casting : Casting = Casting::Unsafe) : T
      dataset.fill_value(T, casting: casting)
    end

    def each_block(*, max_bytes : Int, casting : Casting = Casting::Unsafe,
                   &block : Selection, Array(T) ->) : Nil
      dataset.each_block(T, max_bytes: max_bytes, casting: casting, &block)
    end

    def each_chunk(*, casting : Casting = Casting::Unsafe, &block : Selection, Array(T) ->) : Nil
      dataset.each_chunk(T, casting: casting, &block)
    end

    def [](selection : Selection) : Array(T)
      read(selection)
    end

    def []=(selection : Selection, data) : Nil
      write(data, selection)
    end
  end
end
