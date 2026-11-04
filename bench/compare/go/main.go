// SPDX-License-Identifier: Apache-2.0
package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
)

func temporal(value time.Time) []any {
	kind := "offset-datetime"
	var offset any
	year, month, day := value.Date()
	hour, minute, second := value.Clock()
	nanos := value.Nanosecond()
	switch value.Location().String() {
	case "datetime-local":
		kind = "local-datetime"
	case "date-local":
		kind = "local-date"
		hour, minute, second, nanos = 0, 0, 0, 0
	case "time-local":
		kind = "local-time"
		year, month, day = 0, 0, 0
	default:
		_, seconds := value.Zone()
		if seconds%60 != 0 {
			panic("offset is not an integral minute")
		}
		offset = seconds / 60
	}
	return []any{kind, year, int(month), day, hour, minute, second, nanos, offset}
}

func temporalKind(value time.Time) int {
	switch value.Location().String() {
	case "datetime-local":
		return 1
	case "date-local":
		return 2
	case "time-local":
		return 3
	default:
		return 0
	}
}

func semantic(value any) any {
	switch value := value.(type) {
	case time.Time:
		return map[string]any{"$toml_temporal": temporal(value)}
	case float64:
		number := strconv.FormatFloat(value, 'g', -1, 64)
		if !strings.ContainsAny(number, ".eE") {
			number += ".0"
		}
		return json.Number(number)
	case map[string]any:
		out := make(map[string]any, len(value))
		for key, child := range value {
			out[key] = semantic(child)
		}
		return out
	case []any:
		out := make([]any, len(value))
		for i, child := range value {
			out[i] = semantic(child)
		}
		return out
	case []map[string]any:
		out := make([]any, len(value))
		for i, child := range value {
			out[i] = semantic(child)
		}
		return out
	default:
		return value
	}
}

func visit(value any, stats *[18]int64) {
	stats[0]++
	switch value := value.(type) {
	case map[string]any:
		stats[1]++
		for key, child := range value {
			stats[7] += int64(len(key))
			visit(child, stats)
		}
	case []any:
		stats[2]++
		for _, child := range value {
			visit(child, stats)
		}
	case []map[string]any:
		stats[2]++
		for _, child := range value {
			visit(child, stats)
		}
	case string:
		stats[3]++
		stats[8] += int64(len(value))
	case int64:
		stats[4]++
		stats[9] += value
	case float64:
		stats[5]++
		bits := math.Float64bits(value)
		stats[16] += int64(uint32(bits) ^ uint32(bits>>32))
		if math.Abs(value) <= 1000000 {
			stats[10] += int64(value * 1000)
		}
		if math.Abs(value) > 1000000 || bits == (uint64(1)<<63) || (value != 0 && math.Abs(value) < 2.2250738585072014e-308) {
			stats[17]++
		}
	case bool:
		stats[6]++
		if value {
			stats[11]++
		}
	case time.Time:
		stats[12+temporalKind(value)]++
	default:
		panic(fmt.Sprintf("unsupported corpus type %T", value))
	}
}

//go:noinline
func consumeOutput(value int64) int64 { return value }

func main() {
	if len(os.Args) != 4 {
		panic("usage: runner INPUT ITERATIONS full|root|decode|write|write-decode")
	}
	bytes, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	source := string(bytes)
	iterations, err := strconv.ParseInt(os.Args[2], 10, 64)
	if err != nil || iterations < 1 || iterations > 1000000 {
		panic("invalid iterations")
	}
	mode := os.Args[3]
	if mode != "full" && mode != "root" && mode != "decode" && mode != "write" && mode != "write-decode" {
		panic("invalid mode")
	}
	fingerprint := uint64(14695981039346656037)
	for _, byte := range bytes {
		fingerprint = (fingerprint ^ uint64(byte)) * 1099511628211
	}
	if mode == "decode" {
		var doc map[string]any
		if _, err := toml.Decode(source, &doc); err != nil {
			panic(err)
		}
		if err := json.NewEncoder(os.Stdout).Encode(semantic(doc)); err != nil {
			panic(err)
		}
		return
	}
	if mode == "write" || mode == "write-decode" {
		var doc map[string]any
		if _, err := toml.Decode(source, &doc); err != nil {
			panic(err)
		}
		if mode == "write-decode" {
			output, err := toml.Marshal(doc)
			if err != nil {
				panic(err)
			}
			if _, err := os.Stdout.Write(output); err != nil {
				panic(err)
			}
			return
		}
		var serializedBytes int
		var bytesTotal, consumedTotal int64
		start := time.Now()
		for i := int64(0); i < iterations; i++ {
			output, err := toml.Marshal(doc)
			if err != nil {
				panic(err)
			}
			serializedBytes = len(output)
			var edges int64
			if len(output) != 0 {
				edges = int64(output[0]) + int64(output[len(output)-1])
			}
			bytesTotal += int64(len(output))
			consumedTotal += consumeOutput(int64(len(output)) + edges)
			runtime.KeepAlive(output)
		}
		elapsed := time.Since(start).Nanoseconds()
		runtime.KeepAlive(doc)
		result := struct {
			Iterations      int64  `json:"iterations"`
			InputBytes      int    `json:"input_bytes"`
			Fingerprint     string `json:"input_fnv64"`
			Elapsed         int64  `json:"elapsed_ns"`
			SerializedBytes int    `json:"serialized_bytes"`
			BytesTotal      int64  `json:"output_bytes_total"`
			EdgesTotal      int64  `json:"output_edge_total"`
		}{iterations, len(bytes), strconv.FormatUint(fingerprint, 10), elapsed, serializedBytes, bytesTotal, consumedTotal - bytesTotal}
		if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
			panic(err)
		}
		return
	}
	var total [18]int64
	var roots int64
	start := time.Now()
	for i := int64(0); i < iterations; i++ {
		// Decode into a fresh map. GC stays enabled with its normal defaults.
		var doc map[string]any
		if _, err := toml.Decode(source, &doc); err != nil {
			panic(err)
		}
		roots += int64(len(doc))
		if mode == "full" {
			var stats [18]int64
			visit(doc, &stats)
			for j, value := range stats {
				total[j] += value
			}
		}
		runtime.KeepAlive(doc)
	}
	elapsed := time.Since(start).Nanoseconds()
	count := 12
	for _, value := range total[12:16] {
		if value != 0 {
			count = 16
			break
		}
	}
	if total[17] != 0 {
		count = 17
		total[10] = 0
	}
	result := struct {
		Iterations  int64   `json:"iterations"`
		InputBytes  int     `json:"input_bytes"`
		Fingerprint string  `json:"input_fnv64"`
		Elapsed     int64   `json:"elapsed_ns"`
		Roots       int64   `json:"root_total"`
		Stats       []int64 `json:"stats_total"`
	}{iterations, len(bytes), strconv.FormatUint(fingerprint, 10), elapsed, roots, total[:count]}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		panic(err)
	}
}
