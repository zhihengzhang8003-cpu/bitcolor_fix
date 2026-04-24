#!/usr/bin/env python3
"""
BitColor CPU vs FPGA 性能比较测试 - 优化版
适配 EP4CE10: 最大64顶点, 512边
"""

import serial
import sys
import time
import random
from collections import defaultdict

#============================================================================
# 图生成器
#============================================================================

def generate_dense_graph(vertices, density=0.7, seed=42):
    """生成密集图"""
    random.seed(seed)
    edges = []
    for i in range(vertices):
        for j in range(i + 1, vertices):
            if random.random() < density:
                edges.append((i, j))
    return vertices, edges

#============================================================================
# CPU 图着色算法
#============================================================================

def cpu_greedy_coloring(vertices, edges, iterations):
    """CPU贪心图着色 - 多次迭代"""
    adj = defaultdict(set)
    for u, v in edges:
        adj[u].add(v)
        adj[v].add(u)
    
    colors = [0] * vertices
    
    start_time = time.perf_counter()
    
    for _ in range(iterations):
        for vertex in range(vertices):
            used = set()
            for neighbor in adj[vertex]:
                if neighbor < vertex:
                    used.add(colors[neighbor])
            
            color = 0
            while color in used:
                color += 1
            colors[vertex] = color
    
    elapsed = time.perf_counter() - start_time
    color_count = max(colors) + 1 if colors else 0
    return color_count, colors, elapsed

#============================================================================
# FPGA 通信
#============================================================================

class BitColorFPGA:
    CMD_LOAD = 0x01
    CMD_RUN = 0x02
    CMD_READ = 0x03
    CMD_SET_ITER = 0x04
    CMD_READ_TIME = 0x05
    
    def __init__(self, port, baudrate=115200):
        self.ser = serial.Serial(port, baudrate, timeout=5)
        time.sleep(0.1)
        self.ser.reset_input_buffer()
        
    def close(self):
        self.ser.close()
    
    def set_iterations(self, iterations):
        """设置迭代次数"""
        self.ser.write(bytes([self.CMD_SET_ITER]))
        time.sleep(0.02)
        self.ser.write(bytes([(iterations >> 8) & 0xFF]))
        time.sleep(0.02)
        self.ser.write(bytes([iterations & 0xFF]))
        time.sleep(0.1)
        
        if self.ser.in_waiting > 0:
            ack = self.ser.read(1)
            return ack[0] == 0xBB
        return False
    
    def load_graph(self, vertices, edges):
        """加载图数据"""
        adjacency = [[] for _ in range(vertices)]
        for u, v in edges:
            adjacency[u].append(v)
            adjacency[v].append(u)
        
        offset = [0]
        edge_list = []
        for adj in adjacency:
            edge_list.extend(adj)
            offset.append(len(edge_list))
        
        if vertices > 64 or len(edge_list) > 512:
            print(f"  错误: 图太大! 顶点:{vertices}/64, CSR边:{len(edge_list)}/512")
            print(f"  提示: 实际边数最多256条（CSR双向存储）")
            return False
        
        print(f"  图: {vertices}顶点, {len(edges)}边, CSR边:{len(edge_list)}/512")
        
        self.ser.write(bytes([self.CMD_LOAD]))
        time.sleep(0.02)
        
        self.ser.write(bytes([vertices]))
        time.sleep(0.01)
        
        self.ser.write(bytes([(len(edge_list) >> 8) & 0xFF]))
        time.sleep(0.01)
        self.ser.write(bytes([len(edge_list) & 0xFF]))
        time.sleep(0.01)
        
        for o in offset:
            self.ser.write(bytes([(o >> 8) & 0xFF]))
            time.sleep(0.005)
            self.ser.write(bytes([o & 0xFF]))
            time.sleep(0.005)
        
        for e in edge_list:
            self.ser.write(bytes([e]))
            time.sleep(0.005)
        
        time.sleep(0.2)
        if self.ser.in_waiting > 0:
            return self.ser.read(1)[0] == 0xAA
        return True
    
    def run_coloring(self):
        self.ser.reset_input_buffer()
        self.ser.write(bytes([self.CMD_RUN]))
    
    def read_time(self):
        self.ser.reset_input_buffer()
        self.ser.write(bytes([self.CMD_READ_TIME]))
        time.sleep(0.3)
        
        cycles = 0
        for _ in range(4):
            time.sleep(0.05)
            if self.ser.in_waiting > 0:
                cycles = (cycles << 8) | self.ser.read(1)[0]
            else:
                return None
        
        seconds = cycles / 50_000_000.0
        return cycles, seconds
    
    def read_results(self, vertex_count):
        self.ser.reset_input_buffer()
        self.ser.write(bytes([self.CMD_READ]))
        time.sleep(0.3)
        
        color_count = 0
        if self.ser.in_waiting > 0:
            color_count = self.ser.read(1)[0]
        
        colors = []
        for _ in range(vertex_count):
            time.sleep(0.03)
            if self.ser.in_waiting > 0:
                colors.append(self.ser.read(1)[0])
            else:
                colors.append(-1)
        
        return color_count, colors

#============================================================================
# 性能测试
#============================================================================

def verify_coloring(vertices, edges, colors):
    for u, v in edges:
        if u < len(colors) and v < len(colors):
            if colors[u] == colors[v] and colors[u] >= 0:
                return False
    return True

def run_quick_test(port):
    """快速测试"""
    print("=" * 60)
    print("快速性能测试")
    print("=" * 60)
    
    vertices = 30
    iterations = 50000  # 增加迭代次数补偿
    
    v, edges = generate_dense_graph(vertices, density=0.5)  # ~217边, CSR~434
    print(f"\n图配置: {vertices}顶点, {len(edges)}边, {iterations}次迭代")
    
    # CPU测试
    print("\n[CPU测试]")
    cpu_colors, _, cpu_time = cpu_greedy_coloring(v, edges, iterations)
    print(f"  颜色数: {cpu_colors}")
    print(f"  耗时: {cpu_time:.3f} 秒")
    
    # FPGA测试
    print("\n[FPGA测试]")
    try:
        fpga = BitColorFPGA(port)
        fpga.load_graph(v, edges)
        fpga.set_iterations(iterations)
        
        print("  运行中...")
        fpga.run_coloring()
        
        # 等待完成
        for i in range(60):
            time.sleep(1)
            result = fpga.read_time()
            if result and result[0] > 0:
                fpga_cycles, fpga_time = result
                break
            print(f"  等待... {i+1}秒", end='\r')
        else:
            fpga_time = 60
            fpga_cycles = 0
        
        print(f"\n  周期: {fpga_cycles:,}")
        print(f"  耗时: {fpga_time:.3f} 秒")
        
        fpga_colors, colors = fpga.read_results(v)
        print(f"  颜色数: {fpga_colors}")
        
        fpga.close()
        
    except Exception as e:
        print(f"  错误: {e}")
        fpga_time = float('inf')
    
    # 结果
    print("\n" + "=" * 60)
    print(f"CPU:  {cpu_time:.3f} 秒")
    print(f"FPGA: {fpga_time:.3f} 秒")
    if fpga_time > 0:
        print(f"加速比: {cpu_time/fpga_time:.2f}x")

def run_extended_test(port):
    """扩展测试 (>1分钟)"""
    print("=" * 60)
    print("扩展性能测试 (目标: CPU和FPGA都>1分钟)")
    print("=" * 60)
    
    vertices = 35
    iterations = 200000  # 20万次迭代，确保时间足够长
    
    v, edges = generate_dense_graph(vertices, density=0.4)  # ~238边, CSR~476
    print(f"\n测试配置:")
    print(f"  顶点: {vertices}")
    print(f"  边数: {len(edges)} (CSR: {len(edges)*2})")
    print(f"  迭代: {iterations}")
    
    # 先估算CPU时间
    print("\n[估算CPU时间]")
    _, _, sample = cpu_greedy_coloring(v, edges, 1000)
    estimated = sample * (iterations / 1000)
    print(f"  预估: {estimated:.1f} 秒")
    
    # CPU完整测试
    print("\n[CPU完整测试]")
    print("  运行中...")
    start = time.time()
    cpu_colors, cpu_result, cpu_time = cpu_greedy_coloring(v, edges, iterations)
    print(f"  完成! 耗时: {cpu_time:.2f} 秒")
    print(f"  颜色数: {cpu_colors}")
    print(f"  验证: {'通过' if verify_coloring(v, edges, cpu_result) else '失败'}")
    
    # FPGA测试
    print("\n[FPGA测试]")
    try:
        fpga = BitColorFPGA(port)
        
        print("  加载图...")
        if not fpga.load_graph(v, edges):
            print("  加载失败!")
            return
        
        print(f"  设置迭代: {iterations}")
        if fpga.set_iterations(iterations):
            print("  设置成功")
        
        print("  启动...")
        fpga.run_coloring()
        
        print("  等待完成...")
        start = time.time()
        
        while time.time() - start < 300:  # 5分钟超时
            elapsed = int(time.time() - start)
            print(f"  已运行: {elapsed}秒", end='\r')
            time.sleep(2)
            
            result = fpga.read_time()
            if result and result[0] > 0:
                fpga_cycles, fpga_time = result
                print(f"\n  完成! 周期: {fpga_cycles:,}")
                print(f"  耗时: {fpga_time:.2f} 秒")
                break
        else:
            print("\n  超时!")
            fpga_time = 300
        
        fpga_color_count, fpga_colors = fpga.read_results(v)
        print(f"  颜色数: {fpga_color_count}")
        print(f"  验证: {'通过' if verify_coloring(v, edges, fpga_colors) else '失败'}")
        
        fpga.close()
        
    except Exception as e:
        print(f"  错误: {e}")
        import traceback
        traceback.print_exc()
        fpga_time = float('inf')
    
    # 最终结果
    print("\n" + "=" * 60)
    print("最终结果")
    print("=" * 60)
    print(f"图规模: {vertices}顶点, {len(edges)}边")
    print(f"迭代次数: {iterations}")
    print()
    print(f"CPU总耗时:  {cpu_time:.2f} 秒")
    print(f"FPGA总耗时: {fpga_time:.2f} 秒")
    
    if fpga_time > 0 and fpga_time != float('inf'):
        speedup = cpu_time / fpga_time
        print()
        if speedup > 1:
            print(f"★ FPGA比CPU快 {speedup:.2f} 倍")
        else:
            print(f"★ CPU比FPGA快 {1/speedup:.2f} 倍")

def main():
    if len(sys.argv) < 2:
        print("BitColor CPU vs FPGA 性能测试")
        print()
        print("用法: python performance_test.py <COM端口> [quick|extended]")
        print()
        print("  quick    - 快速测试 (~10秒)")
        print("  extended - 扩展测试 (>1分钟)")
        print()
        print("例如:")
        print("  python performance_test.py COM3 quick")
        print("  python performance_test.py COM3 extended")
        return
    
    port = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "quick"
    
    if mode == "extended":
        run_extended_test(port)
    else:
        run_quick_test(port)

if __name__ == "__main__":
    main()
