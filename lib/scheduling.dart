// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

class SchedulingScreen extends StatefulWidget {
  @override
  _SchedulingScreenState createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen> {
  final DatabaseReference database = FirebaseDatabase.instance.ref();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> schedules = [];
  String formattedTime = "";

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadSchedules();
    _updateCurrentTime();
  }

  void _updateCurrentTime() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        formattedTime = "${DateTime.now()}";
      });
    });
  }

  void _loadSchedules() {
    database.child("schedules").onValue.listen((event) {
      if (event.snapshot.exists) {
        Map<String, dynamic> data =
            Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          schedules = data.entries.map((e) {
            return {
              "id": e.key,
              "time": e.value["time"],
              "day": e.value["day"] ?? "Unknown", // Prevents null values
              "enabled": e.value["enabled"] ?? false,
            };
          }).toList();
        });
      }
    });
  }

  void _addSchedule() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime != null) {
      String formattedTime = pickedTime.format(context);

      String? selectedDay = await showDialog(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: Text("Select Day", style: GoogleFonts.poppins(fontSize: 18)),
            children: [
              'Monday',
              'Tuesday',
              'Wednesday',
              'Thursday',
              'Friday',
              'Saturday',
              'Sunday'
            ]
                .map((day) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, day),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child:
                            Text(day, style: GoogleFonts.poppins(fontSize: 16)),
                      ),
                    ))
                .toList(),
          );
        },
      );

      if (selectedDay == null || selectedDay.isEmpty) {
        return; // Prevent saving if no day is selected
      }

      String customKey = "${selectedDay}_${formattedTime.replaceAll(" ", "_")}";

      database.child("schedules").child(customKey).set({
        "time": formattedTime,
        "day": selectedDay,
        "enabled": true,
      });

      // Schedule a notification
      DateTime now = DateTime.now();
      DateTime scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(Duration(days: 1));
      }
      _scheduleNotification(scheduledDate);

      // Add a notification to Firestore
      firestore.collection('notifications').add({
        "title": "New Schedule Added",
        "description": "Scheduled for $selectedDay at $formattedTime",
        "timestamp": Timestamp.now(),
        "type": "Schedule",
      });
    }
  }

  void _scheduleNotification(DateTime scheduledDate) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'The ARCSAI Vacuum is Cleaning',
      'The vacuum process has started',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'your_channel_id',
          'your_channel_name',
          channelDescription: 'your_channel_description',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  void _deleteSchedule(String id) {
    database.child("schedules/$id").remove();
    setState(() {
      schedules.removeWhere((schedule) => schedule["id"] == id);
    });
  }

  Future<bool> _showDeleteConfirmation() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Delete Schedule?",
                style: GoogleFonts.poppins(fontSize: 18)),
            content: Text("This action cannot be undone.",
                style: GoogleFonts.poppins(fontSize: 16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancel", style: GoogleFonts.poppins(fontSize: 14)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Delete",
                    style:
                        GoogleFonts.poppins(fontSize: 14, color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(
          "Schedule",
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 20, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.all(10),
            child: Center(
              child: Text(
                formattedTime.split('.')[0],
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: schedules.isEmpty
          ? Center(
              child: Text(
                "No schedules yet.",
                style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                return Dismissible(
                  key: Key(schedules[index]['id']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Icon(Icons.delete, color: Colors.white, size: 28),
                  ),
                  confirmDismiss: (direction) async {
                    return await _showDeleteConfirmation();
                  },
                  onDismissed: (direction) {
                    _deleteSchedule(schedules[index]['id']);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Schedule deleted'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                    child: ListTile(
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      title: Text(
                          "${schedules[index]['day']} at ${schedules[index]['time']}"),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSchedule,
        child: Icon(Icons.add),
      ),
    );
  }
}
