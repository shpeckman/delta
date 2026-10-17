# bench/diff_bench.cr
require "./bench_helper"

def churn(lines : Array(String), rnd : Random, rate : Float64) : Array(String)
  result = [] of String
  lines.each do |line|
    r = rnd.rand
    if r < rate / 2
      result << "changed #{line}"
    elsif r < rate
    else
      result << line
    end
  end
  result
end

rnd       = Random.new(2024)
small_a   = (1..100).map { |i| "line #{i % 50}" }
small_b   = churn(small_a, rnd, 0.05)
large_a   = (1..50_000).map { |i| "line #{i % 5000}" }
large_b   = churn(large_a, rnd, 0.05)
rewrite_a = (1..10_000).map { |i| "old #{i}" }
rewrite_b = (1..10_000).map { |i| "new #{i}" }

small_old   = small_a.join("\n") + "\n"
small_new   = small_b.join("\n") + "\n"
large_old   = large_a.join("\n") + "\n"
large_new   = large_b.join("\n") + "\n"
rewrite_old = rewrite_a.join("\n") + "\n"
rewrite_new = rewrite_b.join("\n") + "\n"

Benchmark.ips do |x|
  x.report("myers small") { Delta.diff_lines(small_old, small_new) }
  x.report("histogram small") { Delta.diff_lines(small_old, small_new, algorithm: Delta::Histogram.new) }
  x.report("patience small") { Delta.diff_lines(small_old, small_new, algorithm: Delta::Patience.new) }
end

Benchmark.ips do |x|
  x.report("myers 50k lines 5% churn") { Delta.diff_lines(large_old, large_new) }
  x.report("histogram 50k lines 5% churn") { Delta.diff_lines(large_old, large_new, algorithm: Delta::Histogram.new) }
  x.report("patience 50k lines 5% churn") { Delta.diff_lines(large_old, large_new, algorithm: Delta::Patience.new) }
end

Benchmark.ips do |x|
  x.report("myers full rewrite") { Delta.diff_lines(rewrite_old, rewrite_new) }
  x.report("histogram full rewrite") { Delta.diff_lines(rewrite_old, rewrite_new, algorithm: Delta::Histogram.new) }
  x.report("patience full rewrite") { Delta.diff_lines(rewrite_old, rewrite_new, algorithm: Delta::Patience.new) }
end
