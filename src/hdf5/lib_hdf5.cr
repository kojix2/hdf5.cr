@[Link("hdf5")]
lib LibHDF5
  alias Hid = Int64
  alias Herr = Int32
  alias Htri = Int32
  alias Hsize = UInt64
  alias Hssize = Int64

  H5P_DEFAULT    =  0_i64
  H5S_ALL        =  0_i64
  H5_INVALID_HID = -1_i64

  enum TypeClass : Int32
    NoClass   = -1
    Integer   =  0
    Float     =  1
    Time      =  2
    String    =  3
    Bitfield  =  4
    Opaque    =  5
    Compound  =  6
    Reference =  7
    Enum      =  8
    Vlen      =  9
    Array     = 10
    Complex   = 11
  end

  enum Sign : Int32
    Error = -1
    None  =  0
    Two   =  1
  end

  enum CharSet : Int32
    Error = -1
    Ascii =  0
    Utf8  =  1
  end

  enum StrPad : Int32
    Error    = -1
    NullTerm =  0
    NullPad  =  1
    SpacePad =  2
  end

  enum SpaceClass : Int32
    NoClass = -1
    Scalar  =  0
    Simple  =  1
    Null    =  2
  end

  enum IndexType : Int32
    Unknown  = -1
    Name     =  0
    CrtOrder =  1
  end

  enum IterOrder : Int32
    Unknown = -1
    Inc     =  0
    Dec     =  1
    Native  =  2
  end

  enum ObjType : Int32
    Unknown       = -1
    Group         =  0
    Dataset       =  1
    NamedDatatype =  2
    Map           =  3
  end

  enum RefType : Int32
    BadType        = -1
    Object1        =  0
    DatasetRegion1 =  1
    Object2        =  2
    DatasetRegion2 =  3
    Attribute      =  4
    MaxType        =  5
  end

  # Native type global variables (initialized after H5open())
  $h5t_native_int8_g = H5T_NATIVE_INT8_g : Hid
  $h5t_native_uint8_g = H5T_NATIVE_UINT8_g : Hid
  $h5t_native_int16_g = H5T_NATIVE_INT16_g : Hid
  $h5t_native_uint16_g = H5T_NATIVE_UINT16_g : Hid
  $h5t_native_int32_g = H5T_NATIVE_INT32_g : Hid
  $h5t_native_uint32_g = H5T_NATIVE_UINT32_g : Hid
  $h5t_native_int64_g = H5T_NATIVE_INT64_g : Hid
  $h5t_native_uint64_g = H5T_NATIVE_UINT64_g : Hid
  $h5t_native_float_g = H5T_NATIVE_FLOAT_g : Hid
  $h5t_native_double_g = H5T_NATIVE_DOUBLE_g : Hid
  $h5t_c_s1_g = H5T_C_S1_g : Hid
  $h5t_std_ref_g = H5T_STD_REF_g : Hid

  # Library management
  H5E_DEFAULT = 0_i64
  fun H5open : Herr
  fun H5close : Herr
  fun H5get_libversion(majnum : UInt32*, minnum : UInt32*, relnum : UInt32*) : Herr
  fun H5Eset_auto2(estack_id : Hid, func : Void*, client_data : Void*) : Herr

  # File operations
  fun H5Fcreate(filename : UInt8*, flags : UInt32, fcpl_id : Hid, fapl_id : Hid) : Hid
  fun H5Fopen(filename : UInt8*, flags : UInt32, fapl_id : Hid) : Hid
  fun H5Fclose(file_id : Hid) : Herr
  fun H5Fflush(object_id : Hid, scope : Int32) : Herr
  fun H5Fis_accessible(container_name : UInt8*, fapl_id : Hid) : Htri
  fun H5Fget_name(obj_id : Hid, name : UInt8*, size : LibC::SizeT) : LibC::SSizeT

  # Group operations
  fun H5Gcreate2(loc_id : Hid, name : UInt8*, lcpl_id : Hid, gcpl_id : Hid, gapl_id : Hid) : Hid
  fun H5Gopen2(loc_id : Hid, name : UInt8*, gapl_id : Hid) : Hid
  fun H5Gclose(group_id : Hid) : Herr
  fun H5Gget_info(loc_id : Hid, ginfo : GroupInfo*) : Herr

  struct GroupInfo
    storage_type : Int32
    nlinks : Hsize
    max_corder : Int64
    mounted : LibC::Int
  end

  # Link operations (for iterating groups)
  fun H5Lexists(loc_id : Hid, name : UInt8*, lapl_id : Hid) : Htri
  fun H5Lcreate_hard(cur_loc_id : Hid, cur_name : UInt8*, dst_loc_id : Hid, dst_name : UInt8*,
                     lcpl_id : Hid, lapl_id : Hid) : Herr
  fun H5Lcreate_soft(link_target : UInt8*, link_loc_id : Hid, link_name : UInt8*,
                     lcpl_id : Hid, lapl_id : Hid) : Herr
  fun H5Lcreate_external(file_name : UInt8*, obj_name : UInt8*, link_loc_id : Hid,
                         link_name : UInt8*, lcpl_id : Hid, lapl_id : Hid) : Herr
  fun H5Lget_name_by_idx(loc_id : Hid, group_name : UInt8*, idx_type : IndexType,
                         order : IterOrder, n : Hsize, name : UInt8*, size : LibC::SizeT,
                         lapl_id : Hid) : LibC::SSizeT
  fun H5Ldelete(loc_id : Hid, name : UInt8*, lapl_id : Hid) : Herr

  # Dataset operations
  fun H5Dcreate2(loc_id : Hid, name : UInt8*, type_id : Hid, space_id : Hid,
                 lcpl_id : Hid, dcpl_id : Hid, dapl_id : Hid) : Hid
  fun H5Dopen2(loc_id : Hid, name : UInt8*, dapl_id : Hid) : Hid
  fun H5Dclose(dset_id : Hid) : Herr
  fun H5Dread(dset_id : Hid, mem_type_id : Hid, mem_space_id : Hid, file_space_id : Hid,
              plist_id : Hid, buf : Void*) : Herr
  fun H5Dwrite(dset_id : Hid, mem_type_id : Hid, mem_space_id : Hid, file_space_id : Hid,
               plist_id : Hid, buf : Void*) : Herr
  fun H5Dget_space(dset_id : Hid) : Hid
  fun H5Dget_type(dset_id : Hid) : Hid
  fun H5Dget_storage_size(dset_id : Hid) : Hsize
  fun H5Dset_extent(dset_id : Hid, size : Hsize*) : Herr

  # Dataspace operations
  fun H5Screate(type : SpaceClass) : Hid
  fun H5Screate_simple(rank : Int32, dims : Hsize*, maxdims : Hsize*) : Hid
  fun H5Sclose(space_id : Hid) : Herr
  fun H5Sget_simple_extent_ndims(space_id : Hid) : Int32
  fun H5Sget_simple_extent_dims(space_id : Hid, dims : Hsize*, maxdims : Hsize*) : Int32
  fun H5Sget_simple_extent_npoints(space_id : Hid) : Hssize
  fun H5Sget_simple_extent_type(space_id : Hid) : SpaceClass
  fun H5Sselect_hyperslab(space_id : Hid, op : Int32, start : Hsize*, stride : Hsize*,
                          count : Hsize*, block : Hsize*) : Herr
  fun H5Sselect_all(spaceid : Hid) : Herr
  fun H5Sget_select_npoints(spaceid : Hid) : Hssize

  # Datatype operations
  fun H5Tcopy(type_id : Hid) : Hid
  fun H5Tclose(type_id : Hid) : Herr
  fun H5Tget_class(type_id : Hid) : TypeClass
  fun H5Tget_size(type_id : Hid) : LibC::SizeT
  fun H5Tget_sign(type_id : Hid) : Sign
  fun H5Tget_super(type_id : Hid) : Hid
  fun H5Tget_nmembers(type_id : Hid) : Int32
  fun H5Tget_member_name(type_id : Hid, membno : UInt32) : UInt8*
  fun H5Tget_member_offset(type_id : Hid, membno : UInt32) : LibC::SizeT
  fun H5Tget_member_type(type_id : Hid, membno : UInt32) : Hid
  fun H5Tget_array_ndims(type_id : Hid) : Int32
  fun H5Tget_array_dims2(type_id : Hid, dims : Hsize*) : Int32
  fun H5Tget_cset(type_id : Hid) : CharSet
  fun H5Tget_strpad(type_id : Hid) : StrPad
  fun H5Tequal(type1_id : Hid, type2_id : Hid) : Htri
  fun H5Tset_size(type_id : Hid, size : LibC::SizeT) : Herr
  fun H5Tset_cset(type_id : Hid, cset : CharSet) : Herr
  fun H5Tset_strpad(type_id : Hid, strpad : Int32) : Herr
  fun H5Tis_variable_str(type_id : Hid) : Htri
  fun H5Tarray_create2(base_id : Hid, ndims : UInt32, dims : Hsize*) : Hid
  fun H5Tvlen_create(base_id : Hid) : Hid
  fun H5Tcreate(type : TypeClass, size : LibC::SizeT) : Hid
  fun H5Tinsert(parent_id : Hid, name : UInt8*, offset : LibC::SizeT, field_id : Hid) : Herr
  fun H5free_memory(mem : Void*) : Herr
  fun H5Dvlen_reclaim(type_id : Hid, space_id : Hid, plist_id : Hid, buf : Void*) : Herr

  struct VLen
    len : LibC::SizeT
    p : Void*
  end

  # Reference operations
  struct Reference
    data : UInt8[64]
  end

  fun H5Rcreate_object(loc_id : Hid, name : UInt8*, oapl_id : Hid, ref_ptr : Reference*) : Herr
  fun H5Rdestroy(ref_ptr : Reference*) : Herr
  fun H5Ropen_object(ref_ptr : Reference*, rapl_id : Hid, oapl_id : Hid) : Hid
  fun H5Rget_obj_name(ref_ptr : Reference*, rapl_id : Hid, name : UInt8*, size : LibC::SizeT) : LibC::SSizeT
  fun H5Rget_file_name(ref_ptr : Reference*, name : UInt8*, size : LibC::SizeT) : LibC::SSizeT
  fun H5Rget_obj_type3(ref_ptr : Reference*, rapl_id : Hid, obj_type : ObjType*) : Herr

  # Attribute operations
  fun H5Acreate2(loc_id : Hid, attr_name : UInt8*, type_id : Hid, space_id : Hid,
                 acpl_id : Hid, aapl_id : Hid) : Hid
  fun H5Aopen(obj_id : Hid, attr_name : UInt8*, aapl_id : Hid) : Hid
  fun H5Aclose(attr_id : Hid) : Herr
  fun H5Aread(attr_id : Hid, type_id : Hid, buf : Void*) : Herr
  fun H5Awrite(attr_id : Hid, type_id : Hid, buf : Void*) : Herr
  fun H5Aget_space(attr_id : Hid) : Hid
  fun H5Aget_type(attr_id : Hid) : Hid
  fun H5Aget_name(attr_id : Hid, buf_size : LibC::SizeT, buf : UInt8*) : LibC::SSizeT
  fun H5Aexists(obj_id : Hid, attr_name : UInt8*) : Htri
  fun H5Adelete(loc_id : Hid, attr_name : UInt8*) : Herr
  fun H5Aget_num_attrs = H5Aget_storage_size(attr_id : Hid) : Hsize
  fun H5Aopen_by_idx(loc_id : Hid, obj_name : UInt8*, idx_type : IndexType,
                     order : IterOrder, n : Hsize, aapl_id : Hid, lapl_id : Hid) : Hid
  fun H5Aget_name_by_idx(loc_id : Hid, obj_name : UInt8*, idx_type : IndexType,
                         order : IterOrder, n : Hsize, name : UInt8*,
                         size : LibC::SizeT, lapl_id : Hid) : LibC::SSizeT

  # Object operations
  fun H5Oopen(loc_id : Hid, name : UInt8*, lapl_id : Hid) : Hid
  fun H5Oclose(object_id : Hid) : Herr
  fun H5Oget_info3(loc_id : Hid, oinfo : ObjInfo*, fields : UInt32) : Herr

  struct ObjInfo
    fileno : UInt64
    token : ObjToken
    type : ObjType
    rc : UInt32
    atime : LibC::TimeT
    mtime : LibC::TimeT
    ctime : LibC::TimeT
    btime : LibC::TimeT
    num_attrs : Hsize
  end

  struct ObjToken
    data : UInt8[16]
  end

  # ID management
  fun H5Iget_type(id : Hid) : Int32

  H5I_GROUP   = 2
  H5I_DATASET = 5

  # Object info field masks
  H5O_INFO_BASIC     = 0x0001_u32
  H5O_INFO_TIME      = 0x0002_u32
  H5O_INFO_NUM_ATTRS = 0x0004_u32
  H5O_INFO_ALL       = 0x0007_u32

  # Property list
  fun H5Pcreate(cls_id : Hid) : Hid
  fun H5Pclose(plist_id : Hid) : Herr
  fun H5Pset_chunk(plist_id : Hid, ndims : Int32, dim : Hsize*) : Herr
  fun H5Pset_deflate(plist_id : Hid, level : UInt32) : Herr
  fun H5Pset_shuffle(plist_id : Hid) : Herr
  fun H5Pset_fletcher32(plist_id : Hid) : Herr
  fun H5Pset_create_intermediate_group(plist_id : Hid, crt_intmd : UInt32) : Herr
  fun H5Pset_fill_value(plist_id : Hid, type_id : Hid, value : Void*) : Herr

  $h5p_cls_dataset_create_id_g = H5P_CLS_DATASET_CREATE_ID_g : Hid
  $h5p_cls_link_create_id_g = H5P_CLS_LINK_CREATE_ID_g : Hid
end
