// SPDX-License-Identifier: Apache-2.0
#include <toml++/toml.hpp>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>

using Stats = std::array<std::int64_t, 18>;
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
    else if (auto value = node.as_floating_point()) {
        ++stats[5]; const double number = value->get(); std::uint64_t bits; std::memcpy(&bits, &number, sizeof(bits));
        stats[16] += static_cast<std::uint32_t>(bits) ^ static_cast<std::uint32_t>(bits >> 32);
        if (std::abs(number) <= 1000000.0) stats[10] += static_cast<std::int64_t>(number * 1000.0);
        if (std::abs(number) > 1000000.0 || bits == (std::uint64_t{1} << 63) || std::fpclassify(number) == FP_SUBNORMAL) ++stats[17];
    }
    else if (auto value = node.as_boolean()) { ++stats[6]; stats[11] += value->get(); }
    else if (auto value = node.as_date_time()) { ++stats[value->get().offset ? 12 : 13]; }
    else if (node.is_date()) ++stats[14];
    else if (node.is_time()) ++stats[15];
    else throw std::runtime_error("unsupported node kind");
}
void quote(std::string_view value, std::ostream& out) {
    out << '"';
    for (unsigned char byte : value) {
        if (byte == '"') out << "\\\"";
        else if (byte == '\\') out << "\\\\";
        else if (byte == '\n') out << "\\n";
        else if (byte == '\r') out << "\\r";
        else if (byte == '\t') out << "\\t";
        else if (byte < 32) { const char* hex = "0123456789abcdef"; out << "\\u00" << hex[byte >> 4] << hex[byte & 15]; }
        else out << static_cast<char>(byte);
    }
    out << '"';
}
void encode(const toml::node& node, std::ostream& out) {
    if (auto table = node.as_table()) {
        out << '{'; bool first = true;
        for (const auto& [key, value] : *table) { if (!first) out << ','; first = false; quote(key.str(), out); out << ':'; encode(value, out); }
        out << '}';
    } else if (auto array = node.as_array()) {
        out << '['; bool first = true;
        for (const auto& value : *array) { if (!first) out << ','; first = false; encode(value, out); }
        out << ']';
    } else if (node.is_date_time() || node.is_date() || node.is_time()) {
        toml::date date{0, 0, 0}; toml::time time{0, 0, 0, 0};
        const char* kind = "local-date"; std::string offset = "null";
        if (auto value = node.as_date_time()) {
            date = value->get().date; time = value->get().time;
            if (value->get().offset) { kind = "offset-datetime"; offset = std::to_string(value->get().offset->minutes); }
            else kind = "local-datetime";
        } else if (auto value = node.as_date()) date = value->get();
        else { kind = "local-time"; time = node.as_time()->get(); }
        out << "{\"$toml_temporal\":[\"" << kind << "\"," << date.year << ',' << int(date.month) << ',' << int(date.day)
            << ',' << int(time.hour) << ',' << int(time.minute) << ',' << int(time.second) << ',' << time.nanosecond << ',' << offset << "]}";
    } else if (node.is_floating_point()) {
        if (node.as_floating_point()->get() == 0.0 && std::signbit(node.as_floating_point()->get())) { out << "-0.0"; return; }
        std::ostringstream buffer; buffer << toml::json_formatter(node);
        const auto number = buffer.str(); out << number;
        if (number.find_first_of(".eE") == std::string::npos) out << ".0";
    } else out << toml::json_formatter(node);
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
            encode(document, std::cout); std::cout << '\n'; return 0;
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
        const std::size_t count = total[17] ? 17 : total[12] || total[13] || total[14] || total[15] ? 16 : 12;
        if (total[17]) total[10] = 0;
        for (std::size_t j = 0; j < count; ++j) { if (j) std::cout << ','; std::cout << total[j]; }
        std::cout << "]}\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
