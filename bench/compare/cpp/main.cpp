// SPDX-License-Identifier: Apache-2.0
#include <toml++/toml.hpp>
#include <array>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>

using Stats = std::array<std::int64_t, 12>;
void visit(const toml::node& node, Stats& stats) {
    ++stats[0];
    if (auto table = node.as_table()) {
        ++stats[1];
        for (const auto& [key, child] : *table) {
            stats[7] += key.str().size(); visit(child, stats);
        }
    } else if (auto array = node.as_array()) {
        ++stats[2]; for (const auto& child : *array) visit(child, stats);
    } else if (auto value = node.as_string()) { ++stats[3]; stats[8] += value->get().size(); }
    else if (auto value = node.as_integer()) { ++stats[4]; stats[9] += value->get(); }
    else if (auto value = node.as_floating_point()) { ++stats[5]; stats[10] += static_cast<std::int64_t>(value->get() * 1000.0); }
    else if (auto value = node.as_boolean()) { ++stats[6]; stats[11] += value->get(); }
    else throw std::runtime_error("datetime is outside this corpus checksum schema");
}
int main(int argc, char** argv) {
    try {
        if (argc != 4) throw std::runtime_error("usage: runner INPUT ITERATIONS full|root|decode|write|write-decode");
        std::ifstream input(argv[1], std::ios::binary);
        if (!input) throw std::runtime_error("cannot read input");
        const std::string source{std::istreambuf_iterator<char>{input}, {}};
        std::size_t end = 0;
        const auto iterations = std::stoll(argv[2], &end);
        if (argv[2][end] || iterations < 1 || iterations > 1000000) throw std::runtime_error("invalid iterations");
        const std::string mode = argv[3];
        if (mode != "full" && mode != "root" && mode != "decode" && mode != "write" && mode != "write-decode") throw std::runtime_error("invalid mode");
        std::uint64_t fingerprint = 14695981039346656037ULL;
        for (unsigned char byte : source) fingerprint = (fingerprint ^ byte) * 1099511628211ULL;
        if (mode == "decode") {
            const auto document = toml::parse(std::string_view(source));
            std::cout << toml::json_formatter(document) << '\n'; return 0;
        }
        if (mode == "write" || mode == "write-decode") {
            const auto document = toml::parse(std::string_view(source));
            if (mode == "write-decode") {
                std::ostringstream buffer;
                buffer << toml::toml_formatter(document);
                std::cout << buffer.str(); return 0;
            }
            std::int64_t serialized_bytes = 0, bytes_total = 0, consumed_total = 0;
            const auto start = std::chrono::steady_clock::now();
            for (std::int64_t i = 0; i < iterations; ++i) {
                asm volatile("" : : "g"(&document) : "memory");
                std::ostringstream buffer;
                buffer << toml::toml_formatter(document);
                auto output = buffer.str();
                serialized_bytes = output.size();
                const auto edges = output.empty() ? 0 : static_cast<unsigned char>(output.front()) + static_cast<unsigned char>(output.back());
                auto consumed = serialized_bytes + edges;
                asm volatile("" : "+r"(consumed) : "g"(output.data()) : "memory");
                bytes_total += serialized_bytes; consumed_total += consumed;
                // Both the fresh stream buffer and owned string die in scope.
            }
            const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start).count();
            std::cout << "{\"iterations\":" << iterations << ",\"input_bytes\":" << source.size()
                      << ",\"input_fnv64\":\"" << fingerprint << "\",\"elapsed_ns\":" << elapsed
                      << ",\"serialized_bytes\":" << serialized_bytes << ",\"output_bytes_total\":" << bytes_total
                      << ",\"output_edge_total\":" << consumed_total - bytes_total << "}\n";
            return 0;
        }
        Stats total{};
        std::int64_t roots = 0;
        const auto start = std::chrono::steady_clock::now();
        for (std::int64_t i = 0; i < iterations; ++i) {
            auto document = toml::parse(std::string_view(source));
            asm volatile("" : : "g"(&document) : "memory");
            roots += document.size();
            if (mode == "full") {
                Stats stats{}; visit(document, stats);
                for (std::size_t j = 0; j < stats.size(); ++j) total[j] += stats[j];
            }
            // The complete owned document is destroyed before the next iteration.
        }
        const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start).count();
        std::cout << "{\"iterations\":" << iterations << ",\"input_bytes\":" << source.size()
                  << ",\"input_fnv64\":\"" << fingerprint << "\",\"elapsed_ns\":" << elapsed
                  << ",\"root_total\":" << roots << ",\"stats_total\":[";
        for (std::size_t j = 0; j < total.size(); ++j) { if (j) std::cout << ','; std::cout << total[j]; }
        std::cout << "]}\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
