import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _searchTerm = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload History'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search',
                suffixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream:
                  FirebaseFirestore.instance.collection('images').snapshots(),
              // Inside StreamBuilder
              // Inside StreamBuilder
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircularProgressIndicator();
                }
                if (snapshot.hasData) {
                  var filteredDocs = snapshot.data!.docs;
                  if (_searchTerm.isNotEmpty) {
                    try {
                      DateTime searchDate = DateTime.parse(_searchTerm);
                      filteredDocs = filteredDocs.where((doc) {
                        DateTime docDate = doc['timestamp'].toDate();
                        return docDate.year == searchDate.year &&
                            docDate.month == searchDate.month &&
                            docDate.day == searchDate.day;
                      }).toList();
                    } catch (e) {
                      // Handle error or invalid date format
                    }
                  }
                  return ListView(
                    padding: EdgeInsets.all(8.0),
                    children: filteredDocs.map((DocumentSnapshot document) {
                      return Card(
                        child: ListTile(
                          subtitle: Text(
                              'Pipes count ' + document['count'].toString()),
                          contentPadding: EdgeInsets.all(8.0),
                          leading: Image.network(document['url'],
                              width: 100, fit: BoxFit.cover),
                          title:
                              Text(document['timestamp'].toDate().toString()),
                        ),
                      );
                    }).toList(),
                  );
                } else {
                  return Text("No data available");
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pipe Counter',
      home: ImagePickerScreen(),
    );
  }
}

class ImagePickerScreen extends StatefulWidget {
  @override
  _ImagePickerScreenState createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  XFile? _image;
  int? _recognitions;
  String? _savedImagePath; // New variable for saved image path
  Uint8List? _decodedImage;

  // Method to upload image to Firebase Storage
  Future<String?> uploadImageToFirebase(Uint8List imageData) async {
    try {
      // Create a unique file name for the image
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();

      // Reference to Firebase Storage bucket
      firebase_storage.Reference ref = firebase_storage.FirebaseStorage.instance
          .ref()
          .child('uploads')
          .child(fileName);

      // Upload the image to Firebase Storage
      firebase_storage.UploadTask uploadTask = ref.putData(imageData);

      // Wait for the upload to complete
      firebase_storage.TaskSnapshot snapshot = await uploadTask;
      if (snapshot.state == firebase_storage.TaskState.success) {
        // Get image URL from Firebase Storage
        String imageUrl = await snapshot.ref.getDownloadURL();
        return imageUrl;
      } else {
        log('Upload failed');
        return null;
      }
    } catch (e) {
      log(e.toString());
      return null;
    }
  }

  // Method to add image URL to Firestore
  Future<void> saveImageUrlToFirestore(String imageUrl, int pipeCounts) async {
    // Reference to Firestore collection
    CollectionReference imagesCollection =
        FirebaseFirestore.instance.collection('images');

    // Add the image URL to the Firestore collection
    return imagesCollection
        .add(
            {'url': imageUrl, 'count': pipeCounts, 'timestamp': DateTime.now()})
        .then((value) => log("Image URL Added"))
        .catchError((error) => log("Failed to add image URL: $error"));
  }

  @override
  void initState() {
    super.initState();
  }

  void _pickImage() async {
    final ImagePicker _picker = ImagePicker();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _image = image;
      });

      // Upload the image and get recognitions
      var result = await uploadImage(File(image.path));
      if (result != null) {
        setState(() {
          _recognitions = result['count'];
          if (result['image_base64'] != null) {
            _decodedImage = base64Decode(result['image_base64']);
          }
        });

        // After getting the base64 image, upload it to Firebase Storage
        String? imageUrl = await uploadImageToFirebase(_decodedImage!);
        if (imageUrl != null) {
          // After successfully uploading the image, save the URL to Firestore
          await saveImageUrlToFirestore(imageUrl, _recognitions!);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> uploadImage(File imageFile) async {
    var uri =
        Uri.parse('https://d1c9-115-164-119-39.ngrok-free.app/detect_pipes');
    var request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    log('Sending');

    var response = await request.send();

    if (response.statusCode == 200) {
      var responseData = await response.stream.toBytes();
      var responseString = String.fromCharCodes(responseData);
      log("RESPONSE $responseString");
      return jsonDecode(responseString);
    } else {
      // Handle error...
      log('Failed to upload image: ${response.statusCode}');
      return null;
    }
  }

  void _navigateToHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => HistoryScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pipe Counter'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _navigateToHistory, // Make sure to define this method
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _decodedImage != null
                ? Image.memory(_decodedImage!)
                : Text('No processed image available.'),
            Text('Pipes detected: ${_recognitions ?? 0}'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        tooltip: 'Pick Image',
        child: Icon(Icons.add_a_photo),
      ),
    );
  }
}
