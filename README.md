# hdf5.cr

[![CI](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/kojix2/hdf5.cr/actions/workflows/ci.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fhdf5.cr%2Flines)](https://tokei.kojix2.net/github/kojix2/hdf5.cr)
![Static Badge](https://img.shields.io/badge/PURE-Vibe_Coding-magenta)

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
