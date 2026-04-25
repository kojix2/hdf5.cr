module HDF5
  class Error < Exception
  end

  class FileError < Error
  end

  class ObjectNotFoundError < Error
  end

  class AlreadyExistsError < Error
  end

  class TypeMismatchError < Error
  end

  class ShapeMismatchError < Error
  end

  class ClosedObjectError < Error
  end
end
