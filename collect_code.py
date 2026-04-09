#!/usr/bin/env python3
"""Собирает весь код проекта в один .txt файл с путями."""

import os
from pathlib import Path

# Расширения файлов для сбора
EXTENSIONS = {'.dart', '.py', '.js', '.ts', '.java', '.kt', '.swift', '.h', '.hpp', '.c', '.cpp', '.rs', '.go', '.yaml', '.yml', '.json', '.md', '.txt', '.sql', '.sh', '.html', '.css'}

# Папки для игнорирования
IGNORE_DIRS = {'.git', '.dart_tool', '.idea', 'build', 'android', 'ios', 'linux', 'macos', 'windows', 'web', '__pycache__', 'node_modules'}

def collect_code(root_dir: str, output_file: str):
    root = Path(root_dir)
    output = Path(output_file)
    
    collected = []
    
    for path in sorted(root.rglob('*')):
        # Пропускаем папки
        if path.is_dir():
            continue
        
        # Пропускаем игнорируемые директории
        if any(ignore in path.parts for ignore in IGNORE_DIRS):
            continue
        
        # Проверяем расширение
        if path.suffix.lower() not in EXTENSIONS:
            continue
        
        # Пропускаем lock файлы и сгенерированные
        if path.name.endswith('.lock') or path.name == 'pubspec.lock':
            continue
            
        try:
            content = path.read_text(encoding='utf-8')
            rel_path = path.relative_to(root)
            collected.append(f"{'='*60}\n// {rel_path}\n{'='*60}\n{content}\n")
        except Exception as e:
            print(f"⚠️  Не удалось прочитать {rel_path}: {e}")
    
    # Записываем результат
    output.write_text('\n'.join(collected), encoding='utf-8')
    print(f"✅ Собрано {len(collected)} файлов в {output}")

if __name__ == '__main__':
    collect_code('.', 'code_dump.txt')
