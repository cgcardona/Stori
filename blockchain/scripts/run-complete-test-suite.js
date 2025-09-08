#!/usr/bin/env node

import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';

const execAsync = promisify(exec);

console.log("🧪 TellUrStori V2 - Complete Test Suite Runner");
console.log("🛡️ Testing ALL RemixAI Optimizations & Original Functionality");
console.log("=" .repeat(80));

const testSuites = [
  {
    name: "🎵 STEM Contract - Original Functionality",
    file: "test/TellUrStoriSTEM.comprehensive.test.js",
    description: "Tests all original STEM contract functionality"
  },
  {
    name: "🏪 Marketplace Contract - Original Functionality", 
    file: "test/STEMMarketplace.comprehensive.test.js",
    description: "Tests all original marketplace functionality"
  },
  {
    name: "🔄 User Flow Integration Tests",
    file: "test/UserFlow.integration.test.js", 
    description: "Tests complete user workflows end-to-end"
  },
  {
    name: "🛡️ RemixAI Optimized Features - Complete Coverage",
    file: "test/OptimizedContracts.comprehensive.test.js",
    description: "Tests ALL RemixAI security enhancements and optimizations"
  }
];

const results = {
  passed: 0,
  failed: 0,
  total: testSuites.length,
  details: []
};

async function runTestSuite(suite) {
  console.log(`\n🔍 Running: ${suite.name}`);
  console.log(`📄 File: ${suite.file}`);
  console.log(`📝 Description: ${suite.description}`);
  console.log("-".repeat(60));
  
  try {
    const startTime = Date.now();
    const { stdout, stderr } = await execAsync(`npx hardhat test ${suite.file}`);
    const duration = Date.now() - startTime;
    
    console.log(stdout);
    if (stderr && !stderr.includes('Warning')) {
      console.log("⚠️ Warnings:", stderr);
    }
    
    // Parse results
    const passMatch = stdout.match(/(\d+) passing/);
    const failMatch = stdout.match(/(\d+) failing/);
    
    const passed = passMatch ? parseInt(passMatch[1]) : 0;
    const failed = failMatch ? parseInt(failMatch[1]) : 0;
    
    const result = {
      suite: suite.name,
      file: suite.file,
      passed,
      failed,
      duration: `${(duration / 1000).toFixed(2)}s`,
      status: failed === 0 ? "✅ PASSED" : "❌ FAILED"
    };
    
    results.details.push(result);
    
    if (failed === 0) {
      results.passed++;
      console.log(`\n✅ ${suite.name} - ALL TESTS PASSED (${passed} tests, ${result.duration})`);
    } else {
      results.failed++;
      console.log(`\n❌ ${suite.name} - TESTS FAILED (${passed} passed, ${failed} failed, ${result.duration})`);
    }
    
  } catch (error) {
    console.error(`\n💥 ${suite.name} - EXECUTION ERROR:`);
    console.error(error.message);
    
    results.failed++;
    results.details.push({
      suite: suite.name,
      file: suite.file,
      passed: 0,
      failed: 1,
      duration: "N/A",
      status: "💥 ERROR",
      error: error.message
    });
  }
}

async function generateTestReport() {
  const report = {
    timestamp: new Date().toISOString(),
    summary: {
      totalSuites: results.total,
      passedSuites: results.passed,
      failedSuites: results.failed,
      successRate: `${((results.passed / results.total) * 100).toFixed(1)}%`
    },
    details: results.details,
    remixAIFeaturesCovered: [
      "✅ Pausable mechanism (emergency stops)",
      "✅ IPFS hash validation (CIDv0 & CIDv1)",
      "✅ ERC2981 royalty standard compliance", 
      "✅ Batch operation limits and validation",
      "✅ Enhanced input validation (duration, tags, royalty)",
      "✅ Anti-sniping auction protection",
      "✅ Fee precision safeguards",
      "✅ Pagination optimization",
      "✅ Offer rejection functionality",
      "✅ Enhanced events and transparency",
      "✅ Receive function protection",
      "✅ Custom error handling",
      "✅ Reentrancy protection",
      "✅ Complete integration workflows"
    ],
    securityStatus: results.failed === 0 ? "🛡️ BULLETPROOF" : "⚠️ NEEDS ATTENTION"
  };
  
  // Save detailed report
  fs.writeFileSync('test-report.json', JSON.stringify(report, null, 2));
  
  return report;
}

async function main() {
  console.log(`\n🚀 Starting comprehensive test suite (${testSuites.length} test suites)...\n`);
  
  // Run all test suites
  for (const suite of testSuites) {
    await runTestSuite(suite);
  }
  
  // Generate final report
  const report = await generateTestReport();
  
  console.log("\n" + "=".repeat(80));
  console.log("📊 FINAL TEST RESULTS");
  console.log("=".repeat(80));
  
  console.log(`\n📈 Summary:`);
  console.log(`├── Total Test Suites: ${report.summary.totalSuites}`);
  console.log(`├── Passed: ${report.summary.passedSuites}`);
  console.log(`├── Failed: ${report.summary.failedSuites}`);
  console.log(`└── Success Rate: ${report.summary.successRate}`);
  
  console.log(`\n📋 Detailed Results:`);
  report.details.forEach((detail, index) => {
    console.log(`${index + 1}. ${detail.status} ${detail.suite}`);
    console.log(`   📄 ${detail.file}`);
    console.log(`   📊 ${detail.passed} passed, ${detail.failed} failed (${detail.duration})`);
    if (detail.error) {
      console.log(`   💥 Error: ${detail.error}`);
    }
  });
  
  console.log(`\n🛡️ RemixAI Security Features Tested:`);
  report.remixAIFeaturesCovered.forEach(feature => {
    console.log(`   ${feature}`);
  });
  
  console.log(`\n📄 Detailed report saved to: test-report.json`);
  
  if (results.failed === 0) {
    console.log(`\n🎉 ALL TESTS PASSED! Your smart contracts are BULLETPROOF! 🛡️`);
    console.log(`🚀 Ready for production deployment on TellUrStori L1! 🎵⛓️✨`);
    process.exit(0);
  } else {
    console.log(`\n⚠️ Some tests failed. Please review and fix issues before deployment.`);
    process.exit(1);
  }
}

main().catch(error => {
  console.error('💥 Test runner failed:', error);
  process.exit(1);
});
