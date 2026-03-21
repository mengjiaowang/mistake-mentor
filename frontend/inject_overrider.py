import yaml

with open('pubspec.yaml', 'r') as f:
     # 保持注释和原有样式不变？Yaml 模块默认会过滤注释。
     # 为了严防死守不把用户 pubspec.yaml 的注释刷掉，我们可以手动在末尾追加文本，
     # 而不是用 safe_load 覆盖！
     pass

# 采用纯文本追加法：
with open('pubspec.yaml', 'a') as f:
    f.write("\n\ndependency_overrides:\n  flutter_math_fork:\n    path: ./flutter_math_fork\n")
    # 增加子依赖项（以防底层需要类元组声明）
    # f.write("\ndependencies:\n  tuple: ^2.0.0\n") 
    print("Injected dependency_overrides successfully")
