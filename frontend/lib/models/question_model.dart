import 'dart:convert';

class QuestionModel {
  final String id;
  final String imageOriginal;
  final String imageThumbnail;
  final String imageBlank;
  final String questionText;
  final List<String>? options;
  final String knowledgePoint;
  final List<String> analysisSteps;
  final String trapWarning;
  final Map<String, dynamic>? similarQuestion;
  final String status;
  final String nextReviewDate;
  final int currentInterval;
  final List<dynamic>? reviewHistory;
  final String createdAt;
  final List<String> tags; // 新增：标签列表

  QuestionModel({
    required this.id,
    required this.imageOriginal,
    required this.imageThumbnail,
    required this.imageBlank,
    required this.questionText,
    this.options,
    required this.knowledgePoint,
    required this.analysisSteps,
    required this.trapWarning,
    this.similarQuestion,
    required this.status,
    required this.nextReviewDate,
    required this.currentInterval,
    this.reviewHistory,
    required this.createdAt,
    required this.tags,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] ?? '',
      imageOriginal: json['image_original'] ?? '',
      imageThumbnail: json['image_thumbnail'] ?? '',
      imageBlank: json['image_blank'] ?? '',
      questionText: json['question_text'] ?? '',
      options: json['options'] != null ? List<String>.from(json['options']) : null,
      knowledgePoint: json['knowledge_point'] ?? '未归类',
      analysisSteps: json['analysis_steps'] != null ? List<String>.from(json['analysis_steps']) : [],
      trapWarning: json['trap_warning'] ?? '',
      similarQuestion: json['similar_question'],
      status: json['status'] ?? json['mastery_status'] ?? 'unreviewed', // 兼容老字段
      nextReviewDate: json['next_review_date'] ?? '',
      currentInterval: json['current_interval'] ?? 1,
      reviewHistory: json['review_history'] != null ? List<dynamic>.from(json['review_history']) : [],
      createdAt: json['created_at'] ?? '',
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image_original': imageOriginal,
      'image_thumbnail': imageThumbnail,
      'image_blank': imageBlank,
      'question_text': questionText,
      'options': options,
      'knowledge_point': knowledgePoint,
      'analysis_steps': analysisSteps,
      'trap_warning': trapWarning,
      'similar_question': similarQuestion,
      'status': status,
      'next_review_date': nextReviewDate,
      'current_interval': currentInterval,
      'review_history': reviewHistory,
      'created_at': createdAt,
      'tags': tags,
    };
  }
}
