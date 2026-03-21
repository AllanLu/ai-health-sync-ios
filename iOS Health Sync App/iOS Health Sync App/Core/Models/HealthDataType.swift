// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HealthKit

enum HealthDataType: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps
    case distanceWalkingRunning
    case distanceCycling
    case activeEnergyBurned
    case basalEnergyBurned
    case exerciseTime
    case standHours
    case flightsClimbed
    case workouts

    case heartRate
    case restingHeartRate
    case walkingHeartRateAverage
    case heartRateVariability
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bloodOxygen
    case respiratoryRate
    case bodyTemperature
    case vo2Max

    case sleepAnalysis
    case sleepInBed
    case sleepAsleep
    case sleepAwake
    case sleepREM
    case sleepCore
    case sleepDeep

    case weight
    case height
    case bodyMassIndex
    case bodyFatPercentage
    case leanBodyMass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps: return "步数"
        case .distanceWalkingRunning: return "步行+跑步距离"
        case .distanceCycling: return "骑行距离"
        case .activeEnergyBurned: return "活动能量"
        case .basalEnergyBurned: return "基础能量"
        case .exerciseTime: return "运动时间"
        case .standHours: return "站立时间"
        case .flightsClimbed: return "爬楼层数"
        case .workouts: return "锻炼"
        case .heartRate: return "心率"
        case .restingHeartRate: return "静息心率"
        case .walkingHeartRateAverage: return "步行平均心率"
        case .heartRateVariability: return "心率变异性"
        case .bloodPressureSystolic: return "收缩压"
        case .bloodPressureDiastolic: return "舒张压"
        case .bloodOxygen: return "血氧"
        case .respiratoryRate: return "呼吸频率"
        case .bodyTemperature: return "体温"
        case .vo2Max: return "最大摄氧量"
        case .sleepAnalysis: return "睡眠分析"
        case .sleepInBed: return "在床时间"
        case .sleepAsleep: return "睡眠时间"
        case .sleepAwake: return "清醒时间"
        case .sleepREM: return "快速眼动睡眠"
        case .sleepCore: return "核心睡眠"
        case .sleepDeep: return "深度睡眠"
        case .weight: return "体重"
        case .height: return "身高"
        case .bodyMassIndex: return "身体质量指数"
        case .bodyFatPercentage: return "体脂率"
        case .leanBodyMass: return "瘦体重"
        }
    }

    var sampleType: HKSampleType? {
        switch self {
        case .steps: return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .distanceWalkingRunning: return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .distanceCycling: return HKObjectType.quantityType(forIdentifier: .distanceCycling)
        case .activeEnergyBurned: return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .basalEnergyBurned: return HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        case .exerciseTime: return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .standHours: return HKObjectType.quantityType(forIdentifier: .appleStandTime)
        case .flightsClimbed: return HKObjectType.quantityType(forIdentifier: .flightsClimbed)
        case .workouts: return HKObjectType.workoutType()
        case .heartRate: return HKObjectType.quantityType(forIdentifier: .heartRate)
        case .restingHeartRate: return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .walkingHeartRateAverage: return HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)
        case .heartRateVariability: return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .bloodPressureSystolic: return HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)
        case .bloodPressureDiastolic: return HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        case .bloodOxygen: return HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .respiratoryRate: return HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .bodyTemperature: return HKObjectType.quantityType(forIdentifier: .bodyTemperature)
        case .vo2Max: return HKObjectType.quantityType(forIdentifier: .vo2Max)
        case .sleepAnalysis: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepInBed: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepAsleep: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepAwake: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepREM: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepCore: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .sleepDeep: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case .height: return HKObjectType.quantityType(forIdentifier: .height)
        case .bodyMassIndex: return HKObjectType.quantityType(forIdentifier: .bodyMassIndex)
        case .bodyFatPercentage: return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        case .leanBodyMass: return HKObjectType.quantityType(forIdentifier: .leanBodyMass)
        }
    }

    var isCategorySleepType: Bool {
        switch self {
        case .sleepAnalysis, .sleepInBed, .sleepAsleep, .sleepAwake, .sleepREM, .sleepCore, .sleepDeep:
            return true
        default:
            return false
        }
    }
}
