# src/delta/stat.cr
require "./edit"

module Delta
  struct Stat
    getter insertions : Int32
    getter deletions  : Int32

    def initialize(@insertions : Int32, @deletions : Int32)
    end

    def total : Int32
      insertions + deletions
    end

    def_equals_and_hash insertions, deletions

    def to_s(io : IO) : Nil
      io << insertions << " insertions(+), " << deletions << " deletions(-)"
    end
  end
end
