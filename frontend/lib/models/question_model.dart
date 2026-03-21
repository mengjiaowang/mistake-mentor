import 'dart:convert';

class QuestionModel {
  final String id;
  final String imageOriginal;
  final String imageBlank;
  final String questionText;
  final List<String>? options;
  final String knowledgePoint;
  final List<String> analysisSteps;
  final String trapWarning;
  final Map<String, dynamic>? similarQuestion;
  final String masteryStatus;
  final String createdAt;
  final List<String> tags; // 新增：标签列表

  QuestionModel({
    required this.id,
    required this.imageOriginal,
    required this.imageBlank,
    required this.questionText,
    this.options,
    required this.knowledgePoint,
    required this.analysisSteps,
    required this.trapWarning,
    this.similarQuestion,
    required this.masteryStatus,
    required this.createdAt,
    required this.tags,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] ?? '',
      imageOriginal: json['image_original'] ?? '',
      imageBlank: json['image_blank'] ?? '',
      questionText: json['question_text'] ?? '',
      options: json['options'] != null ? List<String>.from(json['options']) : null,
      knowledgePoint: json['knowledge_point'] ?? '未归类',
      analysisSteps: json['analysis_steps'] != null ? List<String>.from(json['analysis_steps']) : [],
      trapWarning: json['trap_warning'] ?? '',
      similarQuestion: json['similar_question'],
      masteryStatus: json['mastery_status'] ?? 'unmastered',
      createdAt: json['created_at'] ?? '',
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image_original': imageOriginal,
      'image_blank': imageBlank,
      'question_text': questionText,
      'options': options,
      'knowledge_point': knowledgePoint,
      'analysis_steps': analysisSteps,
      'trap_warning': trapWarning,
      'similar_question': similarQuestion,
      'mastery_status': masteryStatus,
      'created_at': createdAt,
      'tags': tags,
    };
  }
}
