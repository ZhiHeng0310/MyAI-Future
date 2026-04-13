# 🏥 CareLoop — AI Patient Care System

> Intelligent, agent-powered healthcare companion  
> Built with **Flutter · Firebase · Gemini (Google AI)**

---

## 🚀 Overview

CareLoop is an **AI-powered patient care platform** designed to improve:
- 💊 Medication adherence
- 🧠 Patient monitoring
- ⏱️ Clinic queue management
- 📅 Appointment handling

It acts as a **smart healthcare assistant** for both patients and providers, using **agentic AI workflows** to deliver real-time insights and support.

---

## ✨ Key Features

### 🤖 AI Patient Assistant (Gemini-powered)
- Daily health check-ins
- Medication reminders based on time
- Risk detection (low / medium / high)
- Safe responses (no diagnosis, escalation-aware)

### 💊 Medication Adherence Tracker
- Tracks taken / missed medications
- Smart reminders based on schedule
- Time-aware logic (past vs upcoming meds)

### 🏥 Smart Queue System
- Real-time clinic queue tracking
- Reduces patient waiting uncertainty
- Efficient patient flow management

### 📅 Appointment Management
- Book and manage appointments
- Calendar-based scheduling UI
- Linked with patient records

### 🔥 Firebase Backend
- Authentication (Login/Register)
- Firestore real-time database
- Scalable backend for healthcare data

---

## 🧠 AI Design (Gemini Flash)

CareLoop uses **Gemini Flash** with optimized prompts:

```json
{
  "message": "short patient-friendly response",
  "risk": "low | medium | high",
  "actions": ["suggestion1", "suggestion2"]
}
