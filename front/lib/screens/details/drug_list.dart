import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'drug_detail.dart';

class DrugListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> drugList;

  const DrugListScreen({super.key, required this.drugList});

  @override
  State<DrugListScreen> createState() => _DrugListScreenState();
}

class _DrugListScreenState extends State<DrugListScreen> {
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText sttInstance = stt.SpeechToText();
  bool listening = false;

  @override
  void initState() {
    super.initState();
    _announceDrugList();
  }

  Future<void> _announceDrugList() async {
    if (widget.drugList.isEmpty) return;
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    String text = "총 ${widget.drugList.length}개의 약이 있습니다. ";
    for (int i = 0; i < widget.drugList.length; i++) {
      text += "${i + 1}번, ${widget.drugList[i]["drugName"] ?? "정보 없음"}. ";
    }
    text += "보시려면 번호나 이름을 말씀해주세요.";
    await tts.speak(text);
  }

  Future<void> _startListening() async {
    bool available = await sttInstance.initialize();
    if (available) {
      setState(() => listening = true);
      await tts.stop();
      sttInstance.listen(localeId: "ko_KR", onResult: (result) {
        if (result.finalResult) {
          _handleVoice(result.recognizedWords);
        }
      });
    } else {
      await tts.speak("음성 인식 기능을 사용할 수 없습니다.");
    }
  }

  void _handleVoice(String command) async {
    RegExp number = RegExp(r'(\d+)');
    final match = number.firstMatch(command);
    if (match != null) {
      int idx = int.parse(match.group(1)!) - 1;
      if (idx >= 0 && idx < widget.drugList.length) {
        await tts.speak("${idx + 1}번 약으로 이동합니다.");
        _openDrug(widget.drugList[idx]);
        return;
      }
    }

    for (final drug in widget.drugList) {
      String name = (drug["drugName"] ?? "").toString();
      if (name.isNotEmpty && command.contains(name.replaceAll(" ", ""))) {
        await tts.speak("$name 약으로 이동합니다.");
        _openDrug(drug);
        return;
      }
    }

    await tts.speak("약을 찾지 못했습니다. 다시 말씀해주세요.");
  }

  void _openDrug(Map<String, dynamic> drug) {
    sttInstance.stop();
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => DrugDetailScreen(drugInfo: drug)));
  }

  @override
  void dispose() {
    tts.stop();
    sttInstance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
    );

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: const Text('스캔된 약 목록'),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
        actions: [
          IconButton(
            icon: Icon(listening ? Icons.mic_off : Icons.mic,
                color: listening ? Colors.red : scheme.primary),
            onPressed: () {
              if (listening) {
                sttInstance.stop();
                setState(() => listening = false);
              } else {
                _startListening();
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: widget.drugList.length,
        itemBuilder: (context, i) {
          final drug = widget.drugList[i];
          return ListTile(
            title: Text(drug["drugName"] ?? "이름 없음",
                style: TextStyle(color: scheme.primary)),
            subtitle: Text(drug["manufacturer"] ?? "제조사 없음",
                style: const TextStyle(color: Colors.white70)),
            onTap: () => _openDrug(drug),
          );
        },
      ),
    );
  }
}