# hdf5.cr

HDF5 bindings for Crystal.

## Installation

```yaml
dependencies:
  hdf5:
    github: kojix2/hdf5.cr
```

## Usage

```crystal
require "hdf5"

HDF5::File.open("data.h5", :w) do |file|
  file.write_dataset("values", [1.0, 2.0, 3.0])
  file.set_attribute("title", "example")
end

HDF5::File.open("data.h5", :r) do |file|
  p file.read_dataset("values", Float64)
  p file.get_attribute("title", String)
end
```

## License

MIT
