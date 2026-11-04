// SPDX-License-Identifier: Apache-2.0
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"

	"github.com/BurntSushi/toml"
)

func visit(value any, stats *[12]int64) {
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
		stats[10] += int64(value * 1000)
	case bool:
		stats[6]++
		if value {
			stats[11]++
		}
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
		if err := json.NewEncoder(os.Stdout).Encode(doc); err != nil {
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
	var total [12]int64
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
			var stats [12]int64
			visit(doc, &stats)
			for j, value := range stats {
				total[j] += value
			}
		}
		runtime.KeepAlive(doc)
	}
	elapsed := time.Since(start).Nanoseconds()
	result := struct {
		Iterations  int64     `json:"iterations"`
		InputBytes  int       `json:"input_bytes"`
		Fingerprint string    `json:"input_fnv64"`
		Elapsed     int64     `json:"elapsed_ns"`
		Roots       int64     `json:"root_total"`
		Stats       [12]int64 `json:"stats_total"`
	}{iterations, len(bytes), strconv.FormatUint(fingerprint, 10), elapsed, roots, total}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		panic(err)
	}
}
