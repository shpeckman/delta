# src/delta/workspace.cr
require "./edit"

class Delta::Workspace
  @vf = Slice(Int32).new(0)
  @vb = Slice(Int32).new(0)
  @edits = [] of Edit
  @normalized = [] of Edit
  @compacted = [] of Edit
  @counts_a = Hash(Int32, Int32).new(0)
  @counts_b = Hash(Int32, Int32).new(0)
  @bpos_map = Hash(Int32, Int32).new
  @groups = [] of {Int32, Int32, Int32, Int32}

  def v_arrays(max : Int32) : {Slice(Int32), Slice(Int32)}
    bound = max + (max + 1) // 2
    need = 2 * bound + 3
    if @vf.size < need
      @vf = Slice(Int32).new(need, 0)
      @vb = Slice(Int32).new(need, 0)
    end
    {@vf, @vb}
  end

  def edits : Array(Edit)
    @edits
  end

  def normalized : Array(Edit)
    @normalized
  end

  def compacted : Array(Edit)
    @compacted
  end

  def counts : {Hash(Int32, Int32), Hash(Int32, Int32)}
    {@counts_a, @counts_b}
  end

  def bpos_map : Hash(Int32, Int32)
    @bpos_map
  end

  def groups : Array({Int32, Int32, Int32, Int32})
    @groups
  end
end
