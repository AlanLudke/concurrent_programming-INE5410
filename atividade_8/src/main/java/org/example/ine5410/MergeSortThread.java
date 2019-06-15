package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;

public class MergeSortThread<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull final List<T> list) {
        if (list.size() <= 8192)
            return new MergeSortSerial<T>().sort(list);

        final int mid = list.size() / 2;
        final ArrayList<ArrayList<T>> results = new ArrayList<>();
        results.add(null);

        Thread lThread = new Thread(new Runnable() {
            @Override
            public void run() {
                results.set(0, MergeSortThread.this.sort(list.subList(0, mid)));
            }
        });
        lThread.start();
        ArrayList<T> right = MergeSortThread.this.sort(list.subList(mid, list.size()));

        try {
            lThread.join();
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }
        return MergeSortHelper.merge(results.get(0), right);
    }
}
