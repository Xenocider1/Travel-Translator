import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:translator/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TravelTranslatorApp());
}

class TravelTranslatorApp extends StatelessWidget {
  const TravelTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: const MainTranslatorScreen(),
    );
  }
}

class SoundboardItem {
  String id;
  String category;
  String text; // Teks default (dalam Bahasa Indonesia)
  bool isFavorite;

  SoundboardItem({
    required this.id,
    required this.category,
    required this.text,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'text': text,
        'isFavorite': isFavorite,
      };

  factory SoundboardItem.fromJson(Map<String, dynamic> json) => SoundboardItem(
        id: json['id'],
        category: json['category'],
        text: json['text'],
        isFavorite: json['isFavorite'] ?? false,
      );
}

class MainTranslatorScreen extends StatefulWidget {
  const MainTranslatorScreen({super.key});

  @override
  State<MainTranslatorScreen> createState() => _MainTranslatorScreenState();
}

class _MainTranslatorScreenState extends State<MainTranslatorScreen> {
  // TTS & Translator & Speech
  final FlutterTts _flutterTts = FlutterTts();
  final GoogleTranslator _translator = GoogleTranslator();
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Bahasa Utama (Atas)
  String _sourceLang = 'id';
  String _targetLang = 'ja';

  // Bahasa Voice Translator (Bawah) - Point 1 (Bisa 2 Arah Independen)
  String _voiceSourceLang = 'id';
  String _voiceTargetLang = 'ja';
  bool _isListening = false;
  String _recognizedText = '';
  String _translatedText = '';

  // Data Soundboard & Kategori
  List<String> _categories = ['Umum', 'Makanan', 'Arah', 'Belanja', 'Darurat'];
  String _selectedCategory = 'Favorite'; // Point 6
  List<SoundboardItem> _items = [];
  Map<String, String> _translatedCache = {};

  final Map<String, String> _languageMap = {
    'id': 'Indonesia',
    'ja': 'Jepang',
    'en': 'Inggris',
    'ko': 'Korea',
    'zh-cn': 'Mandarin',
  };

  @override
  void initState() {
    super.initState();
    _initTTS();
    _loadData();
  }

  void _initTTS() async {
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  // Load Data dari SharedPreferences
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Kategori
    final String? catData = prefs.getString('custom_categories');
    if (catData != null) {
      _categories = List<String>.from(json.decode(catData));
    }

    // Load Items
    final String? itemsData = prefs.getString('soundboard_items');
    if (itemsData != null) {
      final List decoded = json.decode(itemsData);
      _items = decoded.map((x) => SoundboardItem.fromJson(x)).toList();
    } else {
      // Data Default
      _items = [
        SoundboardItem(id: '1', category: 'Umum', text: 'Halo / Selamat Pagi', isFavorite: true),
        SoundboardItem(id: '2', category: 'Umum', text: 'Terima Kasih'),
        SoundboardItem(id: '3', category: 'Makanan', text: 'Berapa harganya?'),
        SoundboardItem(id: '4', category: 'Makanan', text: 'Apakah ini halal?'),
        SoundboardItem(id: '5', category: 'Arah', text: 'Di mana toilet?'),
      ];
    }
    setState(() {});
    _translateAllPhrases();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_categories', json.encode(_categories));
    final itemsJson = _items.map((x) => x.toJson()).toList();
    await prefs.setString('soundboard_items', json.encode(itemsJson));
  }

  // Translate otomatis teks soundboard sesuai bahasa awal (Point 8)
  Future<void> _translateAllPhrases() async {
    for (var item in _items) {
      if (_sourceLang == 'id') {
        _translatedCache[item.id] = item.text;
      } else {
        try {
          var translation = await _translator.translate(item.text, from: 'id', to: _sourceLang);
          _translatedCache[item.id] = translation.text;
        } catch (_) {
          _translatedCache[item.id] = item.text;
        }
      }
    }
    if (mounted) setState(() {});
  }

  // Putar Suara TTS (Point 2)
  void _speakPhrase(String text) async {
    try {
      String ttsLang = _targetLang == 'ja' ? 'ja-JP' : _targetLang;
      await _flutterTts.setLanguage(ttsLang);
      var translation = await _translator.translate(text, from: _sourceLang, to: _targetLang);
      await _flutterTts.speak(translation.text);
    } catch (e) {
      await _flutterTts.setLanguage(_targetLang);
      await _flutterTts.speak(text);
    }
  }

  // Swap Bahasa Utama / Atas (Point 4)
  void _swapMainLanguages() {
    setState(() {
      String temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
    });
    _translateAllPhrases();
  }

  // Swap Bahasa Voice Translator / Bawah (Point 1)
  void _swapVoiceLanguages() {
    setState(() {
      String temp = _voiceSourceLang;
      _voiceSourceLang = _voiceTargetLang;
      _voiceTargetLang = temp;
    });
  }

  // Voice Translation (Push-to-Talk)
  void _listenVoice() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() {
          _isListening = true;
          _recognizedText = 'Mendengarkan...';
        });
        _speech.listen(
          localeId: _voiceSourceLang == 'ja' ? 'ja_JP' : 'id_ID',
          onResult: (val) async {
            setState(() {
              _recognizedText = val.recognizedWords;
            });
            if (val.finalResult && _recognizedText.isNotEmpty) {
              var translation = await _translator.translate(
                _recognizedText,
                from: _voiceSourceLang,
                to: _voiceTargetLang,
              );
              setState(() {
                _translatedText = translation.text;
              });
              await _flutterTts.setLanguage(_voiceTargetLang == 'ja' ? 'ja-JP' : _voiceTargetLang);
              await _flutterTts.speak(_translatedText);
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    List<SoundboardItem> displayedItems = _selectedCategory == 'Favorite'
        ? _items.where((x) => x.isFavorite).toList()
        : _items.where((x) => x.category == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Translator', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Kelola Kategori',
            onPressed: _manageCategoriesDialog, // Point 5
          )
        ],
      ),
      body: Column(
        children: [
          // 1. Header Pemilihan Bahasa Utama (Point 4)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLanguageDropdown(_sourceLang, (val) {
                  if (val != null) {
                    setState(() => _sourceLang = val);
                    _translateAllPhrases();
                  }
                }),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 28, color: Colors.indigo),
                  onPressed: _swapMainLanguages,
                  tooltip: 'Tukar Bahasa Utama',
                ),
                _buildLanguageDropdown(_targetLang, (val) {
                  if (val != null) setState(() => _targetLang = val);
                }),
              ],
            ),
          ),

          // 2. Pilihan Kategori (Point 5, 6, 7, 11)
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                const SizedBox(width: 8),
                // Kategori Favorite di Paling Atas (Point 6)
                ChoiceChip(
                  label: const Row(
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.amber),
                      SizedBox(width: 4),
                      Text('Favorite'),
                    ],
                  ),
                  selected: _selectedCategory == 'Favorite',
                  side: BorderSide(color: Colors.indigo.shade300, width: 1.5), // Point 11
                  onSelected: (bool selected) {
                    if (selected) setState(() => _selectedCategory = 'Favorite');
                  },
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedCategory == cat,
                      side: BorderSide(color: Colors.indigo.shade300, width: 1.5), // Point 11: Border terlihat jelas
                      onSelected: (bool selected) {
                        if (selected) setState(() => _selectedCategory = cat);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          // 3. Section Soundboard (Top - Reorderable & Compact) (Point 7, 9)
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ReorderableListView.builder(
                itemCount: displayedItems.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = displayedItems.removeAt(oldIndex);
                    displayedItems.insert(newIndex, item);
                  });
                  _saveData();
                },
                itemBuilder: (context, index) {
                  final item = displayedItems[index];
                  String displayText = _translatedCache[item.id] ?? item.text;

                  return Card(
                    key: ValueKey(item.id),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      height: 55, // Point 9: Tinggi 1/4 standar
                      child: ListTile(
                        dense: true,
                        title: FittedBox( // Point 9: Auto-adjust font size sesuai panjang teks
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            displayText,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Flag / Unflag Favorite (Point 6)
                            IconButton(
                              icon: Icon(
                                item.isFavorite ? Icons.star : Icons.star_border,
                                color: item.isFavorite ? Colors.amber : Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  item.isFavorite = !item.isFavorite;
                                });
                                _saveData();
                              },
                            ),
                            // Edit & Delete (Point 3)
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'edit') _editItemDialog(item);
                                if (val == 'delete') _deleteItem(item);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Hapus')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _speakPhrase(displayText),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Tombol Tambah Frasa (Point 3)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 4),
              child: ElevatedButton.icon(
                onPressed: _addNewItemDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Frasa'),
              ),
            ),
          ),

          const Divider(height: 1, thickness: 2),

          // 4. Section Voice Translator (Bottom - Enlarged) (Point 1, 10)
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.indigo.shade50.withOpacity(0.5),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Tombol Tukar 2 Arah untuk Voice Translator (Point 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_languageMap[_voiceSourceLang] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.swap_calls, color: Colors.indigo, size: 28),
                        onPressed: _swapVoiceLanguages,
                        tooltip: 'Tukar Arah Voice Translate',
                      ),
                      Text(_languageMap[_voiceTargetLang] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Input: $_recognizedText', style: const TextStyle(fontSize: 14)),
                                  const SizedBox(height: 8),
                                  Text('Hasil: $_translatedText', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTapDown: (_) => _listenVoice(),
                          onTapUp: (_) => _listenVoice(),
                          child: CircleAvatar(
                            radius: 35,
                            backgroundColor: _isListening ? Colors.red : Colors.indigo,
                            child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageDropdown(String currentValue, ValueChanged<String?> onChanged) {
    return DropdownButton<String>(
      value: currentValue,
      items: _languageMap.entries.map((e) {
        return DropdownMenuItem(value: e.key, child: Text(e.value));
      }).toList(),
      onChanged: onChanged,
    );
  }

  // --- DIALOGS (TAMBAH, EDIT, KATEGORI) ---
  void _addNewItemDialog() {
    TextEditingController controller = TextEditingController();
    String category = _categories.contains(_selectedCategory) ? _selectedCategory : _categories.first;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Frasa Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Teks Frasa (Bahasa Indonesia)')),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: category,
              isExpanded: true,
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => category = v!,
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _items.add(SoundboardItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    category: category,
                    text: controller.text,
                  ));
                });
                _saveData();
                _translateAllPhrases();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void _editItemDialog(SoundboardItem item) {
    TextEditingController controller = TextEditingController(text: item.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Frasa'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              setState(() => item.text = controller.text);
              _saveData();
              _translateAllPhrases();
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void _deleteItem(SoundboardItem item) {
    setState(() => _items.removeWhere((x) => x.id == item.id));
    _saveData();
  }

  // Kelola Kategori (Tambah & Delete Kategori) - Point 5
  void _manageCategoriesDialog() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kelola Kategori'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Nama Kategori Baru'))),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.indigo),
                      onPressed: () {
                        if (controller.text.isNotEmpty && !_categories.contains(controller.text)) {
                          setState(() => _categories.add(controller.text));
                          setDialogState(() {});
                          _saveData();
                          controller.clear();
                        }
                      },
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _categories.length,
                    itemBuilder: (c, i) => ListTile(
                      title: Text(_categories[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() => _categories.removeAt(i));
                          setDialogState(() {});
                          _saveData();
                        },
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          ],
        ),
      ),
    );
  }
}