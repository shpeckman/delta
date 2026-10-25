# bench/delta/memory_bench.cr
require "../bench_helper"

def human(bytes : Int64) : String
  mb = bytes / 1_048_576.0
  mb >= 1.0 ? "#{mb.round(2)} MB" : "#{(bytes / 1024.0).round(1)} kB"
end

rnd = Random.new(2024)
base = (1..50_000).map { |i| "line #{i % 5000}" }
changed = base.map { |line| rnd.rand < 0.05 ? "changed #{line}" : line }
old = base.join("\n") + "\n"
new = changed.join("\n") + "\n"

la, lb = Delta::Tokenizer.lines(old, new)
tokens_a = la.tokens
tokens_b = lb.tokens

puts "Diff engine allocation (pre-tokenized, 50k lines):"
{"myers" => Delta::Myers.new, "histogram" => Delta::Histogram.new, "patience" => Delta::Patience.new}.each do |name, algorithm|
  ws = Delta::Workspace.new
  algorithm.diff(tokens_a, tokens_b, ws)
  without_ws = Benchmark.memory { algorithm.diff(tokens_a, tokens_b) }
  with_ws = Benchmark.memory { algorithm.diff(tokens_a, tokens_b, ws) }
  puts "  %-9s  without ws %8s   with ws %8s" % {name, human(without_ws), human(with_ws)}
end

puts "\nFull diff_lines allocation (includes tokenization):"
ws = Delta::Workspace.new
Delta.diff_lines(old, new, workspace: ws)
without_ws = Benchmark.memory { Delta.diff_lines(old, new) }
with_ws = Benchmark.memory { Delta.diff_lines(old, new, workspace: ws) }
puts "  myers       without ws %8s   with ws %8s" % {human(without_ws), human(with_ws)}
