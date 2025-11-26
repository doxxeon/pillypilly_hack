import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../api_services/api_helper.dart';

class PrescriptionService {
  final Dio _dio = Dio();
  
  String get _baseUrl => dotenv.env['API_BASE_URL'] ?? '';

  /// ① 처방전 업로드 → /api/v3/prescription-ocr-auto
  Future<Map<String, dynamic>> uploadPrescription(File imageFile) async {
    final url = '$_baseUrl/api/v3/prescription-ocr-auto';
    final allHeaders = await ApiHelper.getAuthHeaders();
    // multipart/form-data 업로드 시 Content-Type은 Dio가 자동으로 설정하므로 제거
    final headers = Map<String, String>.from(allHeaders);
    headers.remove('Content-Type');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path),
    });

    final response = await _dio.post(
      url,
      data: formData,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception('처방전 업로드 실패: ${response.statusCode}');
    }
  }

  /// ② OCR 결과 저장 → /api/v3/prescriptions/{prescription_id}/save-template
  Future<Map<String, dynamic>> saveTemplate(String prescriptionId) async {
    final url = '$_baseUrl/api/v3/prescriptions/$prescriptionId/save-template';
    final headers = await ApiHelper.getAuthHeaders();

    final response = await _dio.post(
      url,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception('템플릿 저장 실패: ${response.statusCode}');
    }
  }

  /// ③ 알약 인식 → /api/v3/image-search
  Future<Map<String, dynamic>> searchPillImage(File imageFile) async {
    final url = '$_baseUrl/api/v3/image-search';
    final allHeaders = await ApiHelper.getAuthHeaders();
    // multipart/form-data 업로드 시 Content-Type은 Dio가 자동으로 설정하므로 제거
    final headers = Map<String, String>.from(allHeaders);
    headers.remove('Content-Type');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path),
    });

    final response = await _dio.post(
      url,
      data: formData,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception('알약 인식 실패: ${response.statusCode}');
    }
  }

  /// ④ 결과 조회 → /api/v3/prescriptions/{prescription_id}/results
  Future<Map<String, dynamic>> getPrescriptionResults(String prescriptionId) async {
    final url = '$_baseUrl/api/v3/prescriptions/$prescriptionId/results';
    final headers = await ApiHelper.getAuthHeaders();

    final response = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception('결과 조회 실패: ${response.statusCode}');
    }
  }

  /// ⑤ 기록함에서 처방전 불러오기 → /api/v3/prescriptions/templates
  Future<List<Map<String, dynamic>>> getTemplates() async {
    final url = '$_baseUrl/api/v3/prescriptions/templates';
    final headers = await ApiHelper.getAuthHeaders();

    final response = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      } else if (response.data is Map && response.data['templates'] != null) {
        return List<Map<String, dynamic>>.from(response.data['templates']);
      }
      return [];
    } else {
      throw Exception('템플릿 조회 실패: ${response.statusCode}');
    }
  }

  /// ⑥ 새로운 세션 생성 → /api/v3/prescriptions/{template_id}/start-session
  Future<Map<String, dynamic>> startSession(String templateId) async {
    final url = '$_baseUrl/api/v3/prescriptions/$templateId/start-session';
    final headers = await ApiHelper.getAuthHeaders();

    debugPrint('📤 [API] POST $url');
    debugPrint('📤 [API] templateId: $templateId');

    try {
      final response = await _dio.post(
        url,
        options: Options(headers: headers),
      );

      debugPrint('📥 [API] 응답 상태: ${response.statusCode}');
      debugPrint('📥 [API] 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        } else {
          throw Exception('세션 생성 실패: 응답 형식이 올바르지 않습니다. ${data.runtimeType}');
        }
      } else {
        throw Exception('세션 생성 실패: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('❌ [API] DioException: ${e.type}');
      debugPrint('❌ [API] 메시지: ${e.message}');
      debugPrint('❌ [API] 응답: ${e.response?.data}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [API] 예외: $e');
      rethrow;
    }
  }

  /// 약봉투 OCR → /api/v3/drugbag-ocr-auto
  Future<Map<String, dynamic>> uploadDrugbagOcr({
    required File imageFile,
    int? expectedCount,
  }) async {
    // 파일 존재 여부 확인
    if (!await imageFile.exists()) {
      throw Exception('이미지 파일을 찾을 수 없습니다.');
    }

    // 파일 크기 확인 (10MB 제한)
    final fileSize = await imageFile.length();
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('이미지 파일 크기가 너무 큽니다. (최대 10MB)');
    }

    final url = '$_baseUrl/api/v3/drugbag-ocr-auto';
    final allHeaders = await ApiHelper.getAuthHeaders();
    // multipart/form-data 업로드 시 Content-Type은 Dio가 자동으로 설정하므로 제거
    final headers = Map<String, String>.from(allHeaders);
    headers.remove('Content-Type');

    try {
      final formDataMap = <String, dynamic>{
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      };
      
      if (expectedCount != null) {
        formDataMap['expected_count'] = expectedCount;
      }

      final formData = FormData.fromMap(formDataMap);

      final response = await _dio.post(
        url,
        data: formData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      // DioException을 그대로 전달하여 상세한 에러 정보 유지
      rethrow;
    } catch (e) {
      // 기타 예외를 DioException으로 변환
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.unknown,
        error: e,
      );
    }
  }

  /// 유통기한 확인 → /api/v3/expiry-date-check
  Future<Map<String, dynamic>> checkExpiryDate(File imageFile) async {
    final url = '$_baseUrl/api/v3/expiry-date-check';
    final allHeaders = await ApiHelper.getAuthHeaders();
    // multipart/form-data 업로드 시 Content-Type은 Dio가 자동으로 설정하므로 제거
    final headers = Map<String, String>.from(allHeaders);
    headers.remove('Content-Type');

    // 파일 존재 여부 확인
    if (!await imageFile.exists()) {
      throw Exception('이미지 파일을 찾을 수 없습니다.');
    }

    // 파일 크기 확인 (10MB 제한)
    final fileSize = await imageFile.length();
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('이미지 파일 크기가 너무 큽니다. (최대 10MB)');
    }

    debugPrint('📤 [API] POST $url');

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });

      final response = await _dio.post(
        url,
        data: formData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      debugPrint('📥 [API] 응답 상태: ${response.statusCode}');
      debugPrint('📥 [API] 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        } else {
          throw Exception('유통기한 확인 실패: 응답 형식이 올바르지 않습니다. ${data.runtimeType}');
        }
      } else {
        throw Exception('유통기한 확인 실패: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('❌ [API] DioException: ${e.type}');
      debugPrint('❌ [API] 메시지: ${e.message}');
      debugPrint('❌ [API] 응답: ${e.response?.data}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [API] 예외: $e');
      rethrow;
    }
  }
}
