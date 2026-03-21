import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // 新增：底层 Canvas 绘制接口
import 'dart:math' as math; // 新增：用于 Cover Fit 计算

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/api_service.dart';

import '../main.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isUploading = false;
  int _cameraIndex = 0;
  bool _isMirrored = false; // 新增：是否开启镜像翻转

  // 新增：保存拍摄后的冷冻帧数据
  Uint8List? _capturedImageBytes;
  ui.Image? _decodedImage; // 新增：解码后的静态画板图像源
  String? _capturedImageName;

  @override
  void initState() {
    super.initState();
    _findBackCamera();
    _initController();
  }

  void _findBackCamera() {
    if (cameras.isEmpty) return;
    int index = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    // 找到后置则使用后置，否则默认第一个
    _cameraIndex = index >= 0 ? index : 0;
  }

  void _initController() {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[_cameraIndex],
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  Future<void> _toggleCamera() async {
    if (cameras.length <= 1) return;
    
    await _controller.dispose();
    setState(() {
      _cameraIndex = (_cameraIndex + 1) % cameras.length;
      _initController();
    });
  }

  @override
  void dispose() {
    if (cameras.isNotEmpty) {
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

      // 后台底层解码，解决 Web 翻转时黑屏渲染 Bug
      ui.decodeImageFromList(bytes, (ui.Image img) {
         if (mounted) setState(() => _decodedImage = img);
      });
    } catch (e) {
      print('Take picture error: $e');
    }
  }

  Future<void> _confirmUpload() async {
    if (_capturedImageBytes == null) return;
    
    try {
      setState(() => _isUploading = true);
      
      final success = await apiService.uploadQuestion(
        _capturedImageBytes!, 
        _capturedImageName ?? "original.jpg",
        mirror: _isMirrored
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
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
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
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            tooltip: '切换摄像头',
            onPressed: _isUploading ? null : _toggleCamera,
          )
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // 核心：若已拍照，显示静态图片，不再刷新相机画面
                Positioned.fill(
                  child: _capturedImageBytes != null
                      ? (_decodedImage != null 
                          ? CustomPaint(painter: ImagePainter(_decodedImage!, _isMirrored))
                          : Image.memory(_capturedImageBytes!, width: double.infinity, height: double.infinity, fit: BoxFit.cover)) // 降级兜底
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(_isMirrored ? 3.1415926535897932 : 0),
                          child: CameraPreview(_controller),
                        ),
                ),
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
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _capturedImageBytes == null
          ? FloatingActionButton(
              onPressed: _isUploading ? null : _takePicture,
              backgroundColor: Colors.white,
              child: const Icon(Icons.camera_alt, color: Colors.indigo, size: 30),
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
                            setState(() {
                              _capturedImageBytes = null; // 撤销冷冻，回到相机
                              _decodedImage = null;       // 静静清理画面缓存
                            });
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
}

class ImagePainter extends CustomPainter {
  final ui.Image image;
  final bool mirror;
  
  ImagePainter(this.image, this.mirror);

  @override
  void paint(Canvas canvas, Size size) {
    if (mirror) {
       canvas.save();
       canvas.translate(size.width, 0);
       canvas.scale(-1, 1);
    }
    
    double srcWidth = image.width.toDouble();
    double srcHeight = image.height.toDouble();
    double scale = math.max(size.width / srcWidth, size.height / srcHeight);
    double dstWidth = srcWidth * scale;
    double dstHeight = srcHeight * scale;
    double left = (size.width - dstWidth) / 2;
    double top = (size.height - dstHeight) / 2;
    
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, srcWidth, srcHeight),
      Rect.fromLTWH(left, top, dstWidth, dstHeight),
      Paint(),
    );
    if (mirror) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldDelegate) => true;
}
