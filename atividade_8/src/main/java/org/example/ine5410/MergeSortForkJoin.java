package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ForkJoinPool;
import java.util.concurrent.ForkJoinTask;
import java.util.concurrent.RecursiveTask;

public class MergeSortForkJoin<T extends Comparable<T>> implements MergeSort<T> {
    private int threads = Runtime.getRuntime().availableProcessors();

    public int getThreads() {
        return threads;
    }

    public void setThreads(int threads) {
        this.threads = threads;
    }

    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull List<T> list) {
        ForkJoinPool pool = new ForkJoinPool(threads);
        ForkJoinTask<ArrayList<T>> future = pool.submit(getTask(list));
        ArrayList<T> result = future.join();
        pool.shutdown(); //no need to wait, no more tasks pending
        return result;
    }

    private RecursiveTask<ArrayList<T>> getTask(final List<T> list) {
        return new RecursiveTask<ArrayList<T>>() {
            @Override
            protected ArrayList<T> compute() {
                if (list.size() <= 512)
                    return new MergeSortSerial<T>().sort(list);

                int mid = list.size() / 2;
                ForkJoinTask<ArrayList<T>> left = getTask(list.subList(0, mid)).fork();
                ForkJoinTask<ArrayList<T>> right = getTask(list.subList(mid, list.size())).fork();
                return MergeSortHelper.merge(left.join(), right.join());
            }
        };
    }
}
