# src/delta/edit.cr
module Delta
  enum Kind : UInt8
    Equal
    Delete
    Insert
  end

  struct Edit
    getter kind : Kind
    getter a_pos : Int32
    getter a_len : Int32
    getter b_pos : Int32
    getter b_len : Int32

    def initialize(@kind : Kind, @a_pos : Int32, @a_len : Int32, @b_pos : Int32, @b_len : Int32)
    end

    def_equals_and_hash kind, a_pos, a_len, b_pos, b_len

    def to_s(io : IO) : Nil
      io << kind << " a[" << a_pos << ", " << a_len << "] b[" << b_pos << ", " << b_len << "]"
    end
  end
end
