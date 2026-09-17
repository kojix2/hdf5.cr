module HDF5
  module Native
    LOCK = Mutex.new(:reentrant)

    def self.synchronize(&)
      LOCK.synchronize { yield }
    end

    {% for name in %w[
                     H5open H5close H5get_libversion H5Eset_auto2 H5Fcreate H5Fopen
                     H5Fclose H5Fflush H5Fis_accessible H5Fget_name H5Gcreate2 H5Gopen2
                     H5Gclose H5Gget_info H5Lexists H5Lcreate_hard H5Lcreate_soft H5Lcreate_external
                     H5Lget_name_by_idx H5Ldelete H5Dcreate2 H5Dopen2 H5Dclose H5Dread
                     H5Dwrite H5Dget_space H5Dget_type H5Dget_storage_size H5Dset_extent H5Screate
                     H5Screate_simple H5Sclose H5Sget_simple_extent_ndims H5Sget_simple_extent_dims H5Sget_simple_extent_npoints H5Sget_simple_extent_type
                     H5Sselect_hyperslab H5Sselect_all H5Sget_select_npoints H5Tcopy H5Tclose H5Tget_class
                     H5Tget_size H5Tget_sign H5Tget_super H5Tget_nmembers H5Tget_member_name H5Tget_member_offset
                     H5Tget_member_type H5Tget_array_ndims H5Tget_array_dims2 H5Tget_cset H5Tget_strpad H5Tequal
                     H5Tset_size H5Tset_cset H5Tset_strpad H5Tis_variable_str H5Tarray_create2 H5Tvlen_create
                     H5Tcreate H5Tinsert H5free_memory H5Dvlen_reclaim H5Rcreate_object H5Rdestroy
                     H5Rcopy H5Ropen_object H5Rget_obj_name H5Rget_file_name H5Rget_obj_type3 H5Acreate2
                     H5Aopen H5Aclose H5Aread H5Awrite H5Aget_space H5Aget_type
                     H5Aget_name H5Aexists H5Adelete H5Aopen_by_idx H5Aget_name_by_idx
                     H5Oopen H5Oclose H5Oget_info3 H5Lmove H5Lget_info2 H5Lget_val
                     H5Lunpack_elink_val H5Arename H5Dget_create_plist H5Pget_layout H5Pget_chunk H5Pget_fill_value
                     H5Tget_order H5Tget_precision H5Tget_offset H5Tenum_create H5Tenum_insert H5Tenum_valueof
                     H5Tget_member_index H5Sselect_none H5Iis_valid H5Zfilter_avail H5Zget_filter_info H5Iget_type
                     H5Pcreate H5Pclose H5Pset_chunk H5Pset_deflate H5Pset_shuffle H5Pset_fletcher32
                     H5Pset_create_intermediate_group H5Pset_fill_value
                   ] %}
      def self.{{ name.downcase.id }}(*args)
        LOCK.synchronize { LibHDF5.{{ name.id }}(*args) }
      end
    {% end %}
  end
end
