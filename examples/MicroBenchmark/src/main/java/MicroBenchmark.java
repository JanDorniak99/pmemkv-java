// SPDX-License-Identifier: BSD-3-Clause
/* Copyright 2021, Intel Corporation */

import io.pmem.pmemkv.Database;
import io.pmem.pmemkv.Converter;
import io.pmem.pmemkv.ByteBufferConverter;

import java.util.concurrent.*;
import java.util.Random;
import java.nio.ByteBuffer;

class StringConverter implements Converter<String> {
	public ByteBuffer toByteBuffer(String entry) {
		return ByteBuffer.wrap(entry.getBytes());
	}

	public String fromByteBuffer(ByteBuffer entry) {
		byte[] bytes;
		bytes = new byte[entry.capacity()];
		entry.get(bytes);
		return new String(bytes);
	}
}

class PutTask implements Runnable {
	private long start, end;
	private Database<String, ByteBuffer> db;

	PutTask(long start, long end, Database<String, ByteBuffer> db) {
		this.start = start;
		this.end = end;
		this.db = db;
	}

	@Override
	public void run() {
		byte[] b = new byte[100];
		new Random().nextBytes(b);

		for (long i = start; i < end; i++) {
			String key = Long.toString(i);
			db.put(key, ByteBuffer.wrap(b));
		}
	}
}

class ReadTask implements Runnable {
	private long start, end;
	private Database<String, ByteBuffer> db;

	ReadTask(long start, long end, Database<String, ByteBuffer> db) {
		this.start = start;
		this.end = end;
		this.db = db;
	}

	@Override
	public void run() {
		for (long i = start; i < end; i++) {
			String key = Long.toString(i);
			db.get(key, (v) -> {
				assert true;
			});
		}
	}
}

public class MicroBenchmark {
	public static void main(String[] args) {
		String engine;
		long count;
		String path;
		int threads;

		if (args.length < 4) {
			System.out.println("Usage: engine count path threadsNumber");
			return;
		}

		engine = args[0];
		count = Long.parseLong(args[1]);
		path = args[2];
		threads = Integer.parseInt(args[3]);

		Database<String, ByteBuffer> db = new Database.Builder<String, ByteBuffer>(engine)
				.setSize(1073741824)
				.setPath(path)
				.setKeyConverter(new StringConverter())
				.setValueConverter(new ByteBufferConverter())
				.setForceCreate(true)
				.build();

		ExecutorService exec = Executors.newFixedThreadPool(threads);
		for (int i = 0; i < threads; ++i) {
			exec.execute(new PutTask(count / threads * i, count / threads * (i + 1), db));
		}

		exec.shutdown();
		try {
			exec.awaitTermination(60000, TimeUnit.SECONDS);
		} catch (InterruptedException e) {
		}

		ExecutorService exec2 = Executors.newFixedThreadPool(threads);
		for (int i = 0; i < threads; ++i) {
			exec2.execute(new ReadTask(count / threads * i, count / threads * (i + 1), db));
		}

		exec2.shutdown();
		try {
			exec2.awaitTermination(60000, TimeUnit.SECONDS);
		} catch (InterruptedException e) {
		}

		db.stop();
	}
}
