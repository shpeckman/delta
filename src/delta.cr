# src/delta.cr
require "./delta/edit"
require "./delta/tokenizer"
require "./delta/algorithm"
require "./delta/myers"
require "./delta/histogram"
require "./delta/patience"
require "./delta/hunk"
require "./delta/unified"

module Delta
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}

  def self.diff(a : Indexable(T), b : Indexable(T), algorithm : Algorithm = Myers.new) : Array(Edit) forall T
    ta, tb = Tokenizer.tokenize(a, b)
    algorithm.diff(ta, tb)
  end

  def self.diff_lines(old_source : String, new_source : String, algorithm : Algorithm = Myers.new) : Array(Edit)
    la, lb = Tokenizer.lines(old_source, new_source)
    algorithm.diff(la.tokens, lb.tokens)
  end

  def self.apply(a : Indexable(T), b : Indexable(T), edits : Array(Edit)) : Array(T) forall T
    result = [] of T
    edits.each do |e|
      case e.kind
      when .equal?  then result.concat(a[e.a_pos, e.a_len])
      when .insert? then result.concat(b[e.b_pos, e.b_len])
      end
    end
    result
  end
end
