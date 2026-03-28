import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

import '../main.dart';

class CaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Uint8List? initialImageBytes;
  final String? initialImageName;

  const CaptureScreen({
    Key? key,
    required this.cameras,
    this.initialImageBytes,
    this.initialImageName,
  }) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isUploading = false;
  int _cameraIndex = 0;
  bool _isMirrored = false;
  int _rotationTurns = 0;
  
  // 裁剪相关状态
  bool _isCropping = false;
  double _cropL = 0.1; // 裁剪框左侧比例
  double _cropT = 0.2; // 裁剪框顶部比例
  double _cropW = 0.6; // 裁剪框宽度比例
  double _cropH = 0.4; // 裁剪框高度比例
  double _boxW = 0;    // 当前绘制容器视口宽度
  double _boxH = 0;    // 当前绘制容器视口高度

  // 保存拍摄后的冷冻帧数据
  Uint8List? _capturedImageBytes;

  String? _capturedImageName;
  
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _capturedImageBytes = widget.initialImageBytes;
    _capturedImageName = widget.initialImageName;

    if (widget.cameras.isNotEmpty) {
      _findBackCamera();
      _initController();
    } else {
      _initializeControllerFuture = Future.value();
    }
  }

  void _findBackCamera() {
    int index = widget.cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    // 找到后置则使用后置，否则默认第一个
    _cameraIndex = index >= 0 ? index : 0;
  }

  void _initController() {
    _controller = CameraController(
      widget.cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false, // 不请求麦克风权限
    );
    _initializeControllerFuture = _controller.initialize();
  }

  Future<void> _toggleCamera() async {
    if (widget.cameras.length <= 1) return;
    
    await _controller.dispose();
    setState(() {
      _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
      _initController();
    });
  }

  @override
  void dispose() {
    if (widget.cameras.isNotEmpty) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      
      final XFile image = await _controller.takePicture();
      final bytes = await image.readAsBytes();
      
      setState(() {
        _capturedImageBytes = bytes;
        _capturedImageName = image.name;
      });


    } catch (e) {
      print('Take picture error: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _capturedImageBytes = bytes;
          _capturedImageName = image.name;
          _rotationTurns = 0; // 重置旋转
          _isMirrored = false; // 重置镜像
        });
      }
    } catch (e) {
      print('Pick image error: $e');
    }
  }

  Future<void> _confirmUpload() async {
    if (_capturedImageBytes == null) return;
    
    try {
      setState(() => _isUploading = true);
      
      // 获取图片的真实尺寸
      final ui.Image decodedImage = await decodeImageFromList(_capturedImageBytes!);
      double actualImgW = decodedImage.width.toDouble();
      double actualImgH = decodedImage.height.toDouble();

      // 计算 BoxFit.cover 缩放及切角偏移
      double imgW = _rotationTurns % 2 == 1 ? actualImgH : actualImgW;
      double imgH = _rotationTurns % 2 == 1 ? actualImgW : actualImgH;

      double scale = _boxW / imgW > _boxH / imgH ? _boxW / imgW : _boxH / imgH; // max
      double renderW = imgW * scale;
      double renderH = imgH * scale;
      double offsetX = (renderW - _boxW) / 2;
      double offsetY = (renderH - _boxH) / 2;

      double imgLeft = (_cropL * _boxW + offsetX) / scale;
      double imgTop = (_cropT * _boxH + offsetY) / scale;
      double imgWidth = (_cropW * _boxW) / scale;
      double imgHeight = (_cropH * _boxH) / scale;

      final success = await apiService.uploadQuestion(
        _capturedImageBytes!, 
        _capturedImageName ?? "original.jpg",
        mirror: _isMirrored,
        rotateDegrees: _rotationTurns * 90,
        cropLeft: _isCropping ? (imgLeft / imgW).clamp(0.0, 1.0) : 0.0,
        cropTop: _isCropping ? (imgTop / imgH).clamp(0.0, 1.0) : 0.0,
        cropWidth: _isCropping ? (imgWidth / imgW).clamp(0.0, 1.0) : 1.0,
        cropHeight: _isCropping ? (imgHeight / imgH).clamp(0.0, 1.0) : 1.0,
      );
      
      setState(() => _isUploading = false);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 错题上传并解析成功！已同步至云端。')),
          );
          Navigator.pop(context, true); // 成功后返回
        }
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('❌ 上传失败，请检查网络或配置')),
           );
        }
      }
    } catch (e) {
      print('Upload error: $e');
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照录入错题'),
        actions: [
          if (_capturedImageBytes != null)
             IconButton(
               icon: Icon(Icons.crop, color: _isCropping ? Colors.orange : Colors.white),
               tooltip: '页面裁剪框选',
               onPressed: () => setState(() => _isCropping = !_isCropping),
             ),
          IconButton(
            icon: Icon(
              _isMirrored ? Icons.flip : Icons.flip_outlined, 
              color: _isMirrored ? Colors.orange : Colors.white
            ),
            tooltip: '镜像翻转 (纠正倒影)',
            onPressed: () {
              setState(() {
                _isMirrored = !_isMirrored;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded, color: Colors.white),
            tooltip: '顺时针顺延90度',
            onPressed: () {
              setState(() {
                _rotationTurns = (_rotationTurns + 1) % 4;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            tooltip: '切换摄像头',
            onPressed: (_isUploading || widget.cameras.length <= 1) ? null : _toggleCamera,
          )
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return LayoutBuilder(
              builder: (context, constraints) {
                _boxW = constraints.maxWidth;
                _boxH = constraints.maxHeight;

                final cropRect = Rect.fromLTWH(
                  _cropL * _boxW, 
                  _cropT * _boxH, 
                  _cropW * _boxW, 
                  _cropH * _boxH
                );

                return Stack(
                  children: [
                    // 核心：始终保持 CameraPreview 在底层，避免 Web 卸载导致黑屏
                    if (widget.cameras.isNotEmpty)
                      Positioned.fill(
                        child: RotatedBox(
                          quarterTurns: _rotationTurns,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(_isMirrored ? 3.1415926535897932 : 0),
                            child: CameraPreview(_controller),
                          ),
                        ),
                      )
                    else 
                      Container(color: Colors.black),
                    // 若已拍照，静态图片覆盖在上面
                    if (_capturedImageBytes != null)
                      Positioned.fill(
                        child: RotatedBox(
                          quarterTurns: _rotationTurns,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(_isMirrored ? 3.1415926535897932 : 0),
                            child: Image.memory(
                              _capturedImageBytes!, 
                              width: double.infinity, 
                              height: double.infinity, 
                              fit: BoxFit.cover
                            ),
                          ),
                        ),
                      ),
                    
                    // 裁剪蒙层与拖拽手柄
                    if (_capturedImageBytes != null && _isCropping) ...[
                      CustomPaint(
                        size: Size.infinite,
                        painter: CropOverlayPainter(cropRect),
                      ),
                      // 中央拖拽移动
                      Positioned.fromRect(
                        rect: cropRect,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              _cropL = (_cropL + d.delta.dx / _boxW).clamp(0.0, 1.0 - _cropW);
                              _cropT = (_cropT + d.delta.dy / _boxH).clamp(0.0, 1.0 - _cropH);
                            });
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      // 四角控制点
                      _buildHandle(
                        left: cropRect.left - 15,
                        top: cropRect.top - 15,
                        onPan: (d) {
                          setState(() {
                            double newL = (_cropL + d.delta.dx / _boxW).clamp(0.0, _cropL + _cropW - 0.1);
                            _cropW = (_cropW + (_cropL - newL)).clamp(0.1, 1.0 - newL);
                            _cropL = newL;
                            double newT = (_cropT + d.delta.dy / _boxH).clamp(0.0, _cropT + _cropH - 0.1);
                            _cropH = (_cropH + (_cropT - newT)).clamp(0.1, 1.0 - newT);
                            _cropT = newT;
                          });
                        }
                      ),
                      _buildHandle(
                        left: cropRect.right - 15,
                        top: cropRect.top - 15,
                        onPan: (d) {
                          setState(() {
                            _cropW = (_cropW + d.delta.dx / _boxW).clamp(0.1, 1.0 - _cropL);
                            double newT = (_cropT + d.delta.dy / _boxH).clamp(0.0, _cropT + _cropH - 0.1);
                            _cropH = (_cropH + (_cropT - newT)).clamp(0.1, 1.0 - newT);
                            _cropT = newT;
                          });
                        }
                      ),
                      _buildHandle(
                        left: cropRect.left - 15,
                        top: cropRect.bottom - 15,
                        onPan: (d) {
                          setState(() {
                            double newL = (_cropL + d.delta.dx / _boxW).clamp(0.0, _cropL + _cropW - 0.1);
                            _cropW = (_cropW + (_cropL - newL)).clamp(0.1, 1.0 - newL);
                            _cropL = newL;
                            _cropH = (_cropH + d.delta.dy / _boxH).clamp(0.1, 1.0 - _cropT);
                          });
                        }
                      ),
                      _buildHandle(
                        left: cropRect.right - 15,
                        top: cropRect.bottom - 15,
                        onPan: (d) {
                          setState(() {
                            _cropW = (_cropW + d.delta.dx / _boxW).clamp(0.1, 1.0 - _cropL);
                            _cropH = (_cropH + d.delta.dy / _boxH).clamp(0.1, 1.0 - _cropT);
                          });
                        }
                      ),
                    ],

                    if (_isUploading)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SpinKitCubeGrid(color: Colors.white, size: 40),
                              SizedBox(height: 16),
                              Text('正在由 AI 处理及解析...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _capturedImageBytes == null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'gallery',
                  onPressed: _isUploading ? null : _pickImageFromGallery,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.photo_library, color: Theme.of(context).primaryColor, size: 28),
                ),
                const SizedBox(width: 40),
                FloatingActionButton(
                  heroTag: 'camera',
                  onPressed: _isUploading ? null : _takePicture,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.camera_alt, color: Theme.of(context).primaryColor, size: 30),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingActionButton(
                    heroTag: 'retake',
                    onPressed: _isUploading
                        ? null
                        : () {
                            if (widget.cameras.isEmpty) {
                              _pickImageFromGallery();
                            } else {
                              setState(() {
                                _capturedImageBytes = null; // 撤销冷冻，回到相机
                              });
                            }
                          },
                    backgroundColor: Colors.red[400],
                    child: const Icon(Icons.refresh, color: Colors.white),
                  ),
                  FloatingActionButton(
                    heroTag: 'upload',
                    onPressed: _isUploading ? null : _confirmUpload,
                    backgroundColor: Colors.green[400],
                    child: const Icon(Icons.cloud_upload, color: Colors.white),
                  ),
                ],
              ),
            ),
    );
  }

  // 辅助构建拖拽手柄
  Widget _buildHandle({required double left, required double top, required Function(DragUpdateDetails) onPan}) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: onPan,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: CircleAvatar(
            radius: 8,
            backgroundColor: Colors.white,
            child: Icon(Icons.circle, size: 10, color: Theme.of(context).primaryColor),
          ),
        ),
      ),
    );
  }
}

// 蒙层绘制：镂空选择框，外围增益黑色遮浮
class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  CropOverlayPainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.5);
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropPath = Path()..addRect(cropRect);
    // 差集镂空
    final path = Path.combine(PathOperation.difference, bgPath, cropPath);
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(cropRect, borderPaint);
    
    // 绘制内点网格虚线/标饰（可省）
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) => oldDelegate.cropRect != cropRect;
}


