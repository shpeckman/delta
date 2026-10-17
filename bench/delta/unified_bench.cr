# bench/delta/unified_bench.cr
require "../bench_helper"

rnd     = Random.new(77)
base    = (1..50_000).map { |i| "line #{i % 5000}" }
changed = base.map { |line| rnd.rand < 0.05 ? "changed #{line}" : line }

old = base.join("\n") + "\n"
new = changed.join("\n") + "\n"

patch = Delta.unified_diff(old, new)
STDOUT.puts "patch size: #{patch.bytesize} bytes"

Benchmark.ips do |x|
  x.report("unified render 50k") { Delta.unified_diff(old, new) }
  x.report("patch parse 50k") { Delta.parse_patch(patch) }
  x.report("patch apply 50k") { Delta.apply_patch(old, patch) }
end
